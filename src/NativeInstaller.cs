using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace IronSun {
 static class NativeInstaller {
  static readonly string[] Required={"Windows/TP_FirstPerson.exe","Windows/Ridgefire/Binaries/Win64/TP_FirstPerson-Win64-Shipping.exe","Windows/Ridgefire/Content/Paks/Ridgefire-Windows.pak","Windows/Ridgefire/Content/Paks/Ridgefire-Windows.ucas","Windows/Ridgefire/Content/Paks/Ridgefire-Windows.utoc"};
  static readonly HashSet<string> RequiredSet=new HashSet<string>(Required,StringComparer.OrdinalIgnoreCase);
  static string Child(string root,string relative) {
   if(String.IsNullOrWhiteSpace(relative)||Path.IsPathRooted(relative)||relative.Contains(':'))throw new IOException("Invalid update path.");
   var parts=relative.Replace('\\','/').Split('/');
   foreach(string p in parts) {
    if(p.Length==0||p=="."||p==".."||p.EndsWith(".")||p.EndsWith(" ")||p.IndexOfAny(Path.GetInvalidFileNameChars())>=0||Regex.IsMatch(p,@"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)",RegexOptions.IgnoreCase))throw new IOException("Unsafe update path.");
   }
   string basis=Path.GetFullPath(root).TrimEnd('\\','/');string path=Path.GetFullPath(Path.Combine(basis,Path.Combine(parts)));
   if(!path.StartsWith(basis+"\\",StringComparison.OrdinalIgnoreCase))throw new IOException("Update path escapes its directory.");
   Settings.EnsurePlain(path);return path;
  }
  static long Number(IDictionary<string,object> d,string key) {object v;if(!d.TryGetValue(key,out v))throw new IOException("Release metadata is incomplete.");return Convert.ToInt64(v);}
  static List<Dictionary<string,object>> Files(Dictionary<string,object> m) {
   object value;if(!m.TryGetValue("files",out value)||!(value is IEnumerable))throw new IOException("Release file inventory is missing.");
   var files=new List<Dictionary<string,object>>();
   foreach(object item in (IEnumerable)value){var d=item as Dictionary<string,object>;if(d==null)throw new IOException("Invalid file inventory.");files.Add(d);}
   return files;
  }
  static void Validate(Dictionary<string,object> m,bool published) {
   string version=Settings.GetString(m,"version");
   if(Number(m,"schema_version")!=1||Settings.GetString(m,"app_id")!="IRON-SUN-LAN"||!Regex.IsMatch(version,@"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))throw new IOException("Unsupported game release.");
   if(Settings.GetString(m,"archive")!="iron-sun-"+version+".zip"||!Regex.IsMatch(Settings.GetString(m,"archive_sha256"),@"^[A-Fa-f0-9]{64}$")||Number(m,"archive_size")<1||Number(m,"archive_size")>10737418240L)throw new IOException("Invalid game download metadata.");
   if(published){
    if(Number(m,"protocol")<58)throw new IOException("This release is incompatible with the current playtest.");
    Uri uri;if(!Uri.TryCreate(Settings.GetString(m,"archive_url"),UriKind.Absolute,out uri)||uri.Scheme!="https"||uri.UserInfo.Length>0)throw new IOException("Game downloads must use HTTPS.");
   }
   var files=Files(m);if(files.Count<5||files.Count>20000)throw new IOException("Invalid release inventory size.");
   var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);long total=0;
   foreach(var f in files){
    string path=Settings.GetString(f,"path");Child(Settings.Root,path);
    if(!path.StartsWith("Windows/",StringComparison.Ordinal)||Regex.IsMatch(path,@"(^|/)(Saved|SaveGames)(/|$)",RegexOptions.IgnoreCase)||!paths.Add(path)||!Regex.IsMatch(Settings.GetString(f,"sha256"),@"^[A-Fa-f0-9]{64}$")||Number(f,"size")<0)throw new IOException("Unsafe or duplicate release file.");
    total=checked(total+Number(f,"size"));if(total>21474836480L)throw new IOException("Release exceeds the supported install size.");
   }
   foreach(string required in Required)if(!paths.Contains(required))throw new IOException("The game release is incomplete.");
  }
  static Dictionary<string,object> ReadRecord(string root) {
   if(!Directory.Exists(root))return null;
   string path=Child(root,"installed.json");
   if(!File.Exists(path))throw new IOException("Existing game folder has no IRON SUN installation record.");
   if(new FileInfo(path).Length>16777216)throw new IOException("Installation record is too large.");
   var data=Settings.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));Validate(data,false);return data;
  }
  static void WriteJson(string path,object data) {
   Settings.EnsurePlain(path);string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
   File.WriteAllText(temp,Settings.Json.Serialize(data),new UTF8Encoding(false));
   if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);
  }
  static void Verify(string root,Dictionary<string,object> m,bool critical) {
   foreach(var f in Files(m)) {
    string relative=Settings.GetString(f,"path");if(critical&&!RequiredSet.Contains(relative))continue;
    string p=Child(root,relative);
    if(!File.Exists(p)||new FileInfo(p).Length!=Number(f,"size")||!String.Equals(Settings.HashFile(p),Settings.GetString(f,"sha256"),StringComparison.OrdinalIgnoreCase))throw new IOException("Game verification failed. Select Repair to restore the published build.");
   }
  }
  static void RemoveOwned(string relative) {
   string p=Child(Settings.Root,relative);
   if(Directory.Exists(p)) {
    foreach(string d in Directory.EnumerateFileSystemEntries(p,"*",SearchOption.AllDirectories))if((File.GetAttributes(d)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked cleanup paths are not supported.");
    Directory.Delete(p,true);
   } else if(File.Exists(p))File.Delete(p);
  }
  static void AssertClosed(){if(Settings.GameRunning())throw new IOException("Close IRON SUN before updating or rolling back.");}
  static void RecoverSwap(string game,string previous) {
   if(!Directory.Exists(game)&&Directory.Exists(previous)){var m=ReadRecord(previous);Verify(previous,m,true);Directory.Move(previous,game);}
  }
  public static Dictionary<string,object> Signed(byte[] bytes,byte[] signature,bool testKey) {
   if(bytes.Length>16777216||signature.Length>1024)throw new IOException("Release metadata is too large.");
   string key=testKey&&!String.IsNullOrEmpty(Settings.TestKey)&&!String.IsNullOrEmpty(Settings.Fixture)?File.ReadAllText(Settings.TestKey):Encoding.UTF8.GetString(Settings.Resource("ReleasePublicKey.xml"));
   using(var rsa=new RSACryptoServiceProvider()){rsa.PersistKeyInCsp=false;rsa.FromXmlString(key);if(!rsa.VerifyData(bytes,"SHA256",signature))throw new IOException("Release signature is invalid. No update was installed.");}
   return Settings.Json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));
  }
  public static async Task<byte[]> Https(string url,int limit) {
   Uri uri;if(!Uri.TryCreate(url,UriKind.Absolute,out uri)||uri.Scheme!="https"||uri.UserInfo.Length>0)throw new IOException("Update metadata must use HTTPS.");
   ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
   using(var client=new HttpClient()){client.Timeout=TimeSpan.FromSeconds(35);client.DefaultRequestHeaders.UserAgent.ParseAdd("IronSunLauncher/1.0.1");
    using(var response=await client.GetAsync(uri,HttpCompletionOption.ResponseHeadersRead)) {
     response.EnsureSuccessStatusCode();if(response.RequestMessage.RequestUri.Scheme!="https")throw new IOException("Update redirect left HTTPS.");
     if(response.Content.Headers.ContentLength>limit)throw new IOException("Update metadata is too large.");
     using(var input=await response.Content.ReadAsStreamAsync())using(var output=new MemoryStream()) {
      var buffer=new byte[65536];int count;
      while((count=await input.ReadAsync(buffer,0,buffer.Length))>0){if(output.Length+count>limit)throw new IOException("Update metadata is too large.");output.Write(buffer,0,count);}return output.ToArray();
     }
    }
   }
  }
  static void Emit(Action<Dictionary<string,object>> callback,string kind,string message,int percent=0,long bytes=0) {
   if(callback==null)return;
   callback(new Dictionary<string,object>{{"type",kind},{"message",message},{"percent",percent},{"bytes",bytes}});
  }
  static async Task Download(Dictionary<string,object> m,string target,Action<Dictionary<string,object>> callback) {
   Settings.EnsurePlain(target);string partial=target+".partial";Settings.EnsurePlain(partial);
   try {
    if(!String.IsNullOrEmpty(Settings.Fixture))File.Copy(Child(Settings.Fixture,Settings.GetString(m,"archive")),partial,true);
    else using(var client=new HttpClient()) {
     client.Timeout=TimeSpan.FromHours(3);client.DefaultRequestHeaders.UserAgent.ParseAdd("IronSunLauncher/1.0.1");
     using(var response=await client.GetAsync(Settings.GetString(m,"archive_url"),HttpCompletionOption.ResponseHeadersRead)) {
      response.EnsureSuccessStatusCode();if(response.RequestMessage.RequestUri.Scheme!="https")throw new IOException("Game download redirect left HTTPS.");
      if(response.Content.Headers.ContentLength.HasValue&&response.Content.Headers.ContentLength.Value!=Number(m,"archive_size"))throw new IOException("Game download length differs from the signed release.");
      using(var input=await response.Content.ReadAsStreamAsync())using(var output=new FileStream(partial,FileMode.Create,FileAccess.Write,FileShare.None)) {
       byte[] buffer=new byte[1048576];long total=0;int count,last=-1;
       while((count=await input.ReadAsync(buffer,0,buffer.Length))>0) {
        total+=count;if(total>Number(m,"archive_size"))throw new IOException("Game download exceeded its signed size.");await output.WriteAsync(buffer,0,count);
        int pct=(int)(100*total/Number(m,"archive_size"));if(pct!=last){last=pct;Emit(callback,"progress","Downloading IRON SUN...",pct,total);}
       }
      }
     }
    }
    if(new FileInfo(partial).Length!=Number(m,"archive_size")||!String.Equals(Settings.HashFile(partial),Settings.GetString(m,"archive_sha256"),StringComparison.OrdinalIgnoreCase))throw new IOException("Downloaded game failed verification. The installed game was preserved.");
    if(File.Exists(target))File.Delete(target);File.Move(partial,target);
   } finally {if(File.Exists(partial))File.Delete(partial);}
  }
  static void Expand(string archive,string root,Dictionary<string,object> m) {
   var inventory=Files(m).ToDictionary(f=>Settings.GetString(f,"path"),StringComparer.OrdinalIgnoreCase);var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   using(var zip=ZipFile.OpenRead(archive)) {
    foreach(var entry in zip.Entries) {
     string name=entry.FullName.Replace('\\','/');
     if(name.EndsWith("/")){Child(root,name.TrimEnd('/'));continue;}
     string p=Child(root,name);
     if(!seen.Add(name)||((entry.ExternalAttributes>>16)&0xF000)==0xA000)throw new IOException("Duplicate or linked archive entry.");
     Dictionary<string,object> record;
     if(!inventory.TryGetValue(name,out record))throw new IOException("Unexpected file in game archive.");
     if(entry.Length!=Number(record,"size"))throw new IOException("Archive file size differs from the release.");
     Directory.CreateDirectory(Path.GetDirectoryName(p));
     using(var input=entry.Open())using(var output=new FileStream(p,FileMode.CreateNew,FileAccess.Write,FileShare.None))input.CopyTo(output);
    }
   }
   Verify(root,m,false);WriteJson(Child(root,"installed.json"),m);
  }
  public static async Task<Dictionary<string,object>> Run(string action,Action<Dictionary<string,object>> callback) {
   if(action!="Check"&&action!="Update"&&action!="Repair"&&action!="Rollback")throw new IOException("Unsupported update action.");
   Settings.EnsureRoot();string game=Child(Settings.Root,"Game"),previous=Child(Settings.Root,"Previous");
   using(var updateLock=new FileStream(Child(Settings.Root,"update.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)) {
    RecoverSwap(game,previous);var installed=ReadRecord(game);
    if(action=="Rollback") {
     AssertClosed();var prior=ReadRecord(previous);if(prior==null)throw new IOException("There is no previous build to restore.");Verify(previous,prior,false);
     string swapName="Rollback-"+Guid.NewGuid().ToString("N"),swap=Child(Settings.Root,swapName);
     try {if(installed!=null)Directory.Move(game,swap);Directory.Move(previous,game);if(Directory.Exists(swap))Directory.Move(swap,previous);}
     catch {if(!Directory.Exists(game)&&Directory.Exists(swap))Directory.Move(swap,game);throw;}
     WriteJson(Child(Settings.Root,"rollback-hold.json"),new{version=Settings.GetString(prior,"version"),feed_version=installed==null?"":Settings.GetString(installed,"version")});
     return Result("ROLLED_BACK",prior,null);
    }
    Emit(callback,"status","Checking the latest playtest release...");Dictionary<string,object> manifest;
    try {
     byte[] bytes,signature;
     if(!String.IsNullOrEmpty(Settings.Fixture)){bytes=File.ReadAllBytes(Child(Settings.Fixture,"game-manifest.json"));signature=File.ReadAllBytes(Child(Settings.Fixture,"game-manifest.sig"));}
     else {bytes=await Https(Settings.ReleaseBase+"game-manifest.json",16777216);signature=await Https(Settings.ReleaseBase+"game-manifest.sig",1024);}
     manifest=Signed(bytes,signature,true);Validate(manifest,true);
    } catch(HttpRequestException) {
     if(installed==null)throw new IOException("Could not reach the release server. Check your connection and retry.");Verify(game,installed,true);return Result("OFFLINE_CURRENT",installed,"Could not check updates. Co-op needs matching builds.");
    } catch(TaskCanceledException) {
     if(installed==null)throw new IOException("The release check timed out. Retry when your connection is available.");Verify(game,installed,true);return Result("OFFLINE_CURRENT",installed,"Could not check updates. Co-op needs matching builds.");
    }
    if(action=="Check")return new Dictionary<string,object>{{"status","AVAILABLE"},{"version",manifest["version"]},{"protocol",manifest["protocol"]},{"archive_size",manifest["archive_size"]},{"release_notes",Settings.GetString(manifest,"release_notes")}};
    string hold=Child(Settings.Root,"rollback-hold.json");
    if(action!="Repair"&&installed!=null&&File.Exists(hold)) {
     var held=Settings.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(hold));
     if(Settings.GetString(held,"version")==Settings.GetString(installed,"version")&&Settings.GetString(held,"feed_version")==Settings.GetString(manifest,"version")){Verify(game,installed,true);return Result("ROLLBACK_HELD",installed,null);}
    }
    if(action!="Repair"&&installed!=null&&Settings.GetString(installed,"version")==Settings.GetString(manifest,"version")){Verify(game,installed,true);var result=Result("CURRENT",installed,null);result["release_notes"]=Settings.GetString(manifest,"release_notes");return result;}
    AssertClosed();long expanded=Files(manifest).Sum(f=>Number(f,"size"));
    if(new DriveInfo(Path.GetPathRoot(Settings.Root)).AvailableFreeSpace<expanded+2*Number(manifest,"archive_size")+536870912L)throw new IOException("Free more disk space before installing IRON SUN.");
    string cache=Child(Settings.Root,"InternetCache");Directory.CreateDirectory(cache);
    string archive=Child(cache,Settings.GetString(manifest,"archive"));
    bool valid=File.Exists(archive)&&new FileInfo(archive).Length==Number(manifest,"archive_size")&&String.Equals(Settings.HashFile(archive),Settings.GetString(manifest,"archive_sha256"),StringComparison.OrdinalIgnoreCase);
    if(!valid){Emit(callback,"status","Downloading IRON SUN...");await Download(manifest,archive,callback);}
    string stageName="Staging-"+Guid.NewGuid().ToString("N"),stage=Child(Settings.Root,stageName);Directory.CreateDirectory(stage);
    try {
     Emit(callback,"status","Verifying game files...");await Task.Run(()=>Expand(archive,stage,manifest));AssertClosed();
     if(Directory.Exists(previous)){ReadRecord(previous);RemoveOwned("Previous");}
     bool moved=false;
     try {if(installed!=null){Directory.Move(game,previous);moved=true;}Directory.Move(stage,game);}
     catch {if(moved&&!Directory.Exists(game))Directory.Move(previous,game);throw;}
     if(File.Exists(hold))File.Delete(hold);
    } finally {RemoveOwned(stageName);}
    foreach(string p in Directory.GetFiles(cache,"iron-sun-*.zip")){Settings.EnsurePlain(p);if(!String.Equals(p,archive,StringComparison.OrdinalIgnoreCase))File.Delete(p);}
    return Result(action=="Repair"?"REPAIRED":"UPDATED",manifest,null);
   }
  }
  static Dictionary<string,object> Result(string status,Dictionary<string,object> m,string warning) {
   var r=new Dictionary<string,object>{{"status",status},{"version",Settings.GetString(m,"version")},{"install_root",Settings.Root},{"warning",warning},{"feed_available",status!="OFFLINE_CURRENT"},{"release_notes",Settings.GetString(m,"release_notes")}};
   object protocol;if(m.TryGetValue("protocol",out protocol))r["protocol"]=protocol;return r;
  }
 }
}
