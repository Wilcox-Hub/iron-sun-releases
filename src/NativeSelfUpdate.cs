using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;

namespace IronSun {
 static class NativeSelfUpdate {
  static string FileIn(string name) {
   string path=Path.Combine(Settings.Root,"Launcher",name);Settings.EnsurePlain(path);return path;
  }
  static Version Validate(Dictionary<string,object> data) {
   Version version;Uri url;long size;
   if(Settings.GetString(data,"schema_version")!="1"||Settings.GetString(data,"app_id")!="IRON-SUN-LAUNCHER"||!Version.TryParse(Settings.GetString(data,"version"),out version)||!Uri.TryCreate(Settings.GetString(data,"url"),UriKind.Absolute,out url)||url.Scheme!="https"||url.UserInfo.Length>0||!Int64.TryParse(Settings.GetString(data,"size_bytes"),out size)||size<1||size>33554432||!System.Text.RegularExpressions.Regex.IsMatch(Settings.GetString(data,"sha256"),"^[A-Fa-f0-9]{64}$"))throw new IOException("Invalid launcher release metadata.");
   return version;
  }
  static void VerifyBinary(string path,Dictionary<string,object> data) {
   Settings.EnsurePlain(path);
   if(new FileInfo(path).Length!=Convert.ToInt64(data["size_bytes"])||!String.Equals(Settings.HashFile(path),Settings.GetString(data,"sha256"),StringComparison.OrdinalIgnoreCase))throw new IOException("Launcher download failed verification.");
   var expected=Validate(data);
   expected=new Version(expected.Major,expected.Minor,Math.Max(0,expected.Build),Math.Max(0,expected.Revision));
   if(new Version(FileVersionInfo.GetVersionInfo(path).FileVersion)!=expected)throw new IOException("Launcher version does not match its signed release.");
  }
  public static async Task<bool> Update() {
   if(Settings.GameRunning())return false;
   if(!String.IsNullOrEmpty(Settings.Fixture)&&String.IsNullOrEmpty(Settings.LauncherTestFeed))return false;
   byte[] bytes,signature;
   try {
    if(!String.IsNullOrEmpty(Settings.LauncherTestFeed)){bytes=File.ReadAllBytes(Path.Combine(Settings.LauncherTestFeed,"launcher-manifest.json"));signature=File.ReadAllBytes(Path.Combine(Settings.LauncherTestFeed,"launcher-manifest.sig"));}
    else {bytes=await NativeInstaller.Https(Settings.ReleaseBase+"launcher-manifest.json",65536);signature=await NativeInstaller.Https(Settings.ReleaseBase+"launcher-manifest.sig",1024);}
   } catch(System.Net.Http.HttpRequestException){return false;}catch(TaskCanceledException){return false;}
   if(bytes.Length>65536)throw new IOException("Launcher metadata is too large.");
   var data=NativeInstaller.Signed(bytes,signature,false);var next=Validate(data);
   if(next<=new Version(Settings.LauncherVersion))return false;
   var content=!String.IsNullOrEmpty(Settings.LauncherTestFeed)?File.ReadAllBytes(Path.Combine(Settings.LauncherTestFeed,"IronSunLauncher.exe")):await NativeInstaller.Https(Settings.GetString(data,"url"),33554432);
   string pending=FileIn("IronSunLauncher.pending.exe");File.WriteAllBytes(pending,content);VerifyBinary(pending,data);
   File.WriteAllBytes(FileIn("pending-manifest.json"),bytes);File.WriteAllBytes(FileIn("pending-manifest.sig"),signature);
   string ready=FileIn("launcher-update-ready.txt");if(File.Exists(ready))File.Delete(ready);
   string error=FileIn("launcher-update-error.txt");if(File.Exists(error))File.Delete(error);
   var args=new List<string>{"--install-root",Settings.Root};
   if(Settings.NoShortcut)args.Add("--no-shortcut");
   if(!String.IsNullOrEmpty(Settings.LauncherTestFeed)){args.AddRange(new[]{"--fixture-feed",Settings.LauncherTestFeed,"--ui-snapshot",FileIn("updated-launcher.png")});}
   string encoded=Convert.ToBase64String(Encoding.UTF8.GetBytes(Settings.Json.Serialize(args)));
   var start=new ProcessStartInfo(pending,"--install-root "+Settings.Quote(Settings.Root)+" --finish-self-update "+Process.GetCurrentProcess().Id+" --next-args "+Settings.Quote(encoded)){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(pending)};
   using(var helper=Process.Start(start)) {
    for(int i=0;i<100&&!File.Exists(ready);i++){if(helper.HasExited)throw new IOException("The launcher update helper could not start.");await Task.Delay(100);}
    if(!File.Exists(ready))throw new IOException("The launcher update could not start. Reopen it to retry.");
   }
   return true;
  }
  public static int Finish(string[] args) {
   try {
    string self=Assembly.GetExecutingAssembly().Location;
    if(!String.Equals(Path.GetFullPath(self),FileIn("IronSunLauncher.pending.exe"),StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid launcher update helper location.");
    byte[] bytes=File.ReadAllBytes(FileIn("pending-manifest.json")),sig=File.ReadAllBytes(FileIn("pending-manifest.sig"));
    if(bytes.Length>65536)throw new IOException("Launcher metadata is too large.");
    var data=NativeInstaller.Signed(bytes,sig,false);VerifyBinary(self,data);
    int index=Array.IndexOf(args,"--finish-self-update"),parent=Int32.Parse(args[index+1]);
    int next=Array.IndexOf(args,"--next-args");
    var childArgs=Settings.Json.Deserialize<string[]>(Encoding.UTF8.GetString(Convert.FromBase64String(args[next+1])));
    File.WriteAllText(FileIn("launcher-update-ready.txt"),"READY");
    try {using(var process=Process.GetProcessById(parent)){if(!process.WaitForExit(30000))throw new IOException("Close the old launcher to finish its update.");}}catch(ArgumentException){}
    string target=FileIn("IronSunLauncher.exe"),temp=FileIn("IronSunLauncher.new.exe"),previous=FileIn("IronSunLauncher.previous.exe");
    File.Copy(self,temp,true);VerifyBinary(temp,data);
    if(File.Exists(previous))File.Delete(previous);
    if(File.Exists(target))File.Replace(temp,target,previous);else File.Move(temp,target);
    File.WriteAllText(FileIn("launcher-update-result.json"),Settings.Json.Serialize(new{status="APPLIED",version=Settings.GetString(data,"version"),sha256=Settings.HashFile(target)}));
    Process.Start(new ProcessStartInfo(target,String.Join(" ",Array.ConvertAll(childArgs,Settings.Quote))){UseShellExecute=false,WorkingDirectory=Settings.Root});
    return 0;
   } catch(Exception ex){File.WriteAllText(FileIn("launcher-update-error.txt"),ex.ToString());return 1;}
  }
 }
}
