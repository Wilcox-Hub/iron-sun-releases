using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;

[assembly: AssemblyTitle("IRON SUN Launcher")]
[assembly: AssemblyDescription("Install, update, and play IRON SUN")]
[assembly: AssemblyCompany("Wilcox-Hub")]
[assembly: AssemblyProduct("IRON SUN")]
[assembly: AssemblyVersion("1.0.1.0")]
[assembly: AssemblyFileVersion("1.0.1.0")]

namespace IronSun {
 static class Settings {
  public const string LauncherVersion="1.0.1";
  public const string ReleaseBase="https://github.com/Wilcox-Hub/iron-sun-releases/releases/latest/download/";
  public const string Website="https://iron-sun-playtest.wilcoxwarrior4577.chatgpt.site";
  public static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=16777216 };
  public static string Root=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"IRON SUN");
  public static string Fixture="";
  public static string TestKey="";
  public static string LauncherTestFeed="";
  public static bool NoShortcut;
  public static string Support {get{return System.IO.Path.Combine(Root,"Launcher","Support",LauncherVersion);}}
  public static byte[] Resource(string name) {
   using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
    if(s==null)throw new InvalidOperationException("Missing launcher resource: "+name);
    using(var b=new MemoryStream()){s.CopyTo(b);return b.ToArray();}
   }
  }
  public static string Quote(string value) {return "\""+value.Replace("\"","\\\"")+"\"";}
  public static string Hash(byte[] b) {using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(b)).Replace("-","");}
  public static string HashFile(string p) {using(var s=File.OpenRead(p))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","");}
  public static string GetString(IDictionary<string,object> data,string key,string fallback="") {object v;return data.TryGetValue(key,out v)&&v!=null?Convert.ToString(v,CultureInfo.InvariantCulture):fallback;}
  public static void EnsurePlain(string path) {
   var cursor=System.IO.Path.GetFullPath(path);
   while(!String.IsNullOrEmpty(cursor)) {
    if((Directory.Exists(cursor)||File.Exists(cursor))&&(File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked install paths are not supported.");
    var p=Directory.GetParent(cursor);cursor=p==null?null:p.FullName;
   }
  }
  public static void EnsureRoot() {
   Root=System.IO.Path.GetFullPath(Root).TrimEnd('\\','/');EnsurePlain(Root);
   var marker=System.IO.Path.Combine(Root,"managed-install.json");
   if(File.Exists(marker)) {
    var data=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(marker));
    if(GetString(data,"app_id")!="IRON-SUN-LAN"||!String.Equals(GetString(data,"root"),Root,StringComparison.OrdinalIgnoreCase))throw new IOException("IRON SUN installation ownership does not match.");
   } else {
    if(Directory.Exists(Root)&&Directory.EnumerateFileSystemEntries(Root).Any())throw new IOException("Choose an empty install folder or the existing managed IRON SUN installation.");
    Directory.CreateDirectory(Root);
    File.WriteAllText(marker,Json.Serialize(new{app_id="IRON-SUN-LAN",root=Root,schema_version=1}),new UTF8Encoding(false));
   }
  }
  public static bool GameRunning() {
   return Process.GetProcessesByName("TP_FirstPerson").Length>0||Process.GetProcessesByName("TP_FirstPerson-Win64-Shipping").Length>0;
  }
 }

 static class Program {
  [STAThread] static int Main(string[] args) {
   try {
    for(int i=0;i<args.Length;i++) {
     if(args[i]=="--install-root"&&i+1<args.Length)Settings.Root=args[++i];
     else if(args[i]=="--fixture-feed"&&i+1<args.Length)Settings.Fixture=args[++i];
     else if(args[i]=="--no-shortcut")Settings.NoShortcut=true;
     else if(args[i]=="--test-key"&&i+1<args.Length)Settings.TestKey=args[++i];
     else if(args[i]=="--self-update-test"&&i+1<args.Length)Settings.LauncherTestFeed=args[++i];
    }
    Settings.EnsureRoot();
    if(args.Contains("--finish-self-update"))return NativeSelfUpdate.Finish(args);
    if(!String.IsNullOrEmpty(Settings.TestKey)&&String.IsNullOrEmpty(Settings.Fixture))throw new IOException("Test keys require a local fixture feed.");
    bool created;
    var name="Local\\IronSunLauncher-"+Settings.Hash(Encoding.UTF8.GetBytes(Settings.Root.ToUpperInvariant())).Substring(0,24);
    using(var mutex=new Mutex(true,name,out created)) {
     if(!created){MessageBox.Show("IRON SUN Launcher is already open.","IRON SUN");return 0;}
     Prepare();
     if(!String.IsNullOrEmpty(Settings.LauncherTestFeed))return Program.UpdateLauncher().GetAwaiter().GetResult()?0:1;
     int command=Array.IndexOf(args,"--update-test");
     if(command>=0) {
      string action=command+1<args.Length?args[command+1]:"Update";
      var result=RunEngine(action,null).GetAwaiter().GetResult();
      Console.WriteLine(Settings.Json.Serialize(result));return 0;
     }
     var app=new Application();app.ShutdownMode=ShutdownMode.OnMainWindowClose;
     var window=new LauncherWindow();
     int shot=Array.IndexOf(args,"--ui-snapshot");
     if(shot>=0&&shot+1<args.Length) {
      window.TestSnapshot=args[shot+1];window.ShowInTaskbar=false;
     }
     app.Run(window);
    }
    return 0;
   } catch(Exception ex) {
    if(args.Contains("--update-test")||args.Contains("--self-update-test")){Console.Error.WriteLine(ex.Message);return 1;}
    MessageBox.Show(ex.Message,"IRON SUN Launcher",MessageBoxButton.OK,MessageBoxImage.Error);return 1;
   }
  }
  static void Prepare() {
   Settings.EnsurePlain(Settings.Support);Directory.CreateDirectory(Settings.Support);
   string launcher=System.IO.Path.Combine(Settings.Root,"Launcher","IronSunLauncher.exe");
   Settings.EnsurePlain(launcher);
   string source=Assembly.GetExecutingAssembly().Location;
   if(!String.Equals(source,launcher,StringComparison.OrdinalIgnoreCase)) {
    if(File.Exists(launcher)&&Settings.HashFile(launcher)!=Settings.HashFile(source)) {
     // An installed launcher verifies its own signed upgrade on startup; do not downgrade it from an old download.
     var v=FileVersionInfo.GetVersionInfo(launcher).FileVersion;
     Version existing;
     if(Version.TryParse(v,out existing)&&existing>new Version(Settings.LauncherVersion))return;
    }
    File.Copy(source,launcher,true);
   }
   if(String.IsNullOrEmpty(Settings.Fixture)&&!Settings.NoShortcut)InstallShortcut(launcher);
  }
  static void InstallShortcut(string launcher) {
   string path=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"IRON SUN.lnk");
   Type type=Type.GetTypeFromProgID("WScript.Shell");object shell=Activator.CreateInstance(type),link=null;
   try {
    link=type.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});
    var t=link.GetType();
    if(File.Exists(path)) {
     var old=Convert.ToString(t.InvokeMember("TargetPath",BindingFlags.GetProperty,null,link,null));
     string legacy=System.IO.Path.Combine(Settings.Root,"Play-IRON-SUN.cmd");
     if(!String.Equals(old,launcher,StringComparison.OrdinalIgnoreCase)&&!String.Equals(old,legacy,StringComparison.OrdinalIgnoreCase))throw new IOException("The existing IRON SUN shortcut belongs to another installation.");
    }
    t.InvokeMember("TargetPath",BindingFlags.SetProperty,null,link,new object[]{launcher});
    t.InvokeMember("WorkingDirectory",BindingFlags.SetProperty,null,link,new object[]{Settings.Root});
    t.InvokeMember("Description",BindingFlags.SetProperty,null,link,new object[]{"Install, update, and play IRON SUN"});
    t.InvokeMember("IconLocation",BindingFlags.SetProperty,null,link,new object[]{launcher});
    t.InvokeMember("Save",BindingFlags.InvokeMethod,null,link,null);
   } finally {
    if(link!=null)System.Runtime.InteropServices.Marshal.FinalReleaseComObject(link);
    System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
   }
  }
  public static Task<Dictionary<string,object>> RunEngine(string action,Action<Dictionary<string,object>> onEvent) {
   return Task.Run(()=>NativeInstaller.Run(action,onEvent));
  }
  public static Task<bool> UpdateLauncher() {return NativeSelfUpdate.Update();}

 }

 class LauncherWindow:Window {
  readonly Brush Amber=new SolidColorBrush(Color.FromRgb(255,182,89));
  readonly Brush Muted=new SolidColorBrush(Color.FromRgb(168,170,165));
  TextBlock status,version,notes,download;
  Button primary,repair,check,rollback;
  ProgressBar progress;
  bool busy,installed;
  string currentAction="Install";
  public string TestSnapshot;
  public LauncherWindow() {
   Title="IRON SUN Launcher";Width=960;Height=660;MinWidth=820;MinHeight=600;WindowStartupLocation=WindowStartupLocation.CenterScreen;WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.CanResizeWithGrip;Background=new SolidColorBrush(Color.FromRgb(15,18,18));Foreground=Brushes.White;FontFamily=new FontFamily("Segoe UI");
   var root=new Grid();root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(74)});root.RowDefinitions.Add(new RowDefinition());root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(72)});Content=root;
   var top=new Grid{Margin=new Thickness(28,0,16,0)};
   top.MouseLeftButtonDown+=(s,e)=>{if(e.ClickCount==2)WindowState=WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized;else DragMove();};
   var brand=new StackPanel{Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};
   var mark=new Ellipse{Width=27,Height=27,Stroke=Amber,StrokeThickness=3,Margin=new Thickness(0,0,14,0)};brand.Children.Add(mark);brand.Children.Add(Text("IRON SUN",23,Brushes.White,FontWeights.SemiBold));brand.Children.Add(Text("  /  PLAYTEST",11,Muted,FontWeights.Normal));top.Children.Add(brand);
   var controls=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Center};
   var min=Button("—",false);min.Width=36;min.Height=34;min.Click+=(s,e)=>WindowState=WindowState.Minimized;
   var close=Button("×",false);close.Width=36;close.Height=34;close.Click+=(s,e)=>Close();controls.Children.Add(min);controls.Children.Add(close);top.Children.Add(controls);root.Children.Add(top);
   var body=new Grid();body.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});body.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(360)});Grid.SetRow(body,1);root.Children.Add(body);
   var art=new Grid{ClipToBounds=true};
   var image=new Image{Stretch=Stretch.UniformToFill};var bitmap=new BitmapImage();using(var stream=new MemoryStream(Settings.Resource("arena-preview.png"))){bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();bitmap.Freeze();}image.Source=bitmap;art.Children.Add(image);
   art.Children.Add(new Border{Background=new LinearGradientBrush(new GradientStopCollection{new GradientStop(Color.FromArgb(30,0,0,0),0),new GradientStop(Color.FromArgb(235,12,16,16),1)},new Point(0,0),new Point(0,1))});
   var title=new StackPanel{Margin=new Thickness(32,0,30,32),VerticalAlignment=VerticalAlignment.Bottom};
   title.Children.Add(Text("SURVIVE. ADVANCE. REPEAT.",11,Amber,FontWeights.SemiBold));title.Children.Add(Text("IRON\nSUN",66,Brushes.White,FontWeights.Bold));
   var pitch=Text("One squad. Arena after arena.\nEarn your way to the next gate.",17,Brushes.White,FontWeights.Normal);pitch.Margin=new Thickness(0,12,0,24);title.Children.Add(pitch);
   title.Children.Add(Text("ARENA ENVIRONMENT PREVIEW",9,Muted,FontWeights.Normal));art.Children.Add(title);body.Children.Add(art);
   var side=new StackPanel{Margin=new Thickness(28,20,28,20)};
   var sideScroll=new ScrollViewer{Content=side,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};Grid.SetColumn(sideScroll,1);body.Children.Add(sideScroll);
   side.Children.Add(Text("INTERNAL ALPHA",11,Amber,FontWeights.SemiBold));
   var heading=Text("Your next run.",29,Brushes.White,FontWeights.SemiBold);heading.Margin=new Thickness(0,13,0,8);side.Children.Add(heading);
   side.Children.Add(Text("The launcher keeps your game updated\nand your saved progress in place.",14,Muted,FontWeights.Normal));
   version=Text("Checking installed build...",12,Muted,FontWeights.Normal);version.Margin=new Thickness(0,18,0,12);side.Children.Add(version);
   primary=Button("Install IRON SUN",true);primary.Height=54;primary.Click+=async(s,e)=>{if(currentAction=="Play")LaunchGame();else await Operate("Update");};side.Children.Add(primary);
   status=Text("Preparing launcher...",13,Brushes.White,FontWeights.Normal);status.TextWrapping=TextWrapping.Wrap;status.Margin=new Thickness(0,12,0,8);status.MinHeight=30;side.Children.Add(status);
   progress=new ProgressBar{Height=4,Foreground=Amber,Background=new SolidColorBrush(Color.FromRgb(42,47,46)),Visibility=Visibility.Collapsed};side.Children.Add(progress);
   download=Text("",11,Muted,FontWeights.Normal);download.Margin=new Thickness(0,7,0,12);side.Children.Add(download);
   var actions=new StackPanel{Orientation=Orientation.Horizontal};
   check=Button("Check updates",false);check.Margin=new Thickness(0,0,10,0);check.Click+=async(s,e)=>await Operate("Update");
   repair=Button("Repair",false);repair.Click+=async(s,e)=>await Operate("Repair");actions.Children.Add(check);actions.Children.Add(repair);side.Children.Add(actions);
   var line=new Border{Height=1,Background=new SolidColorBrush(Color.FromRgb(49,54,52)),Margin=new Thickness(0,18,0,14)};side.Children.Add(line);
   side.Children.Add(Text("LATEST PLAYTEST",10,Muted,FontWeights.SemiBold));
   notes=Text("Updates and release notes appear here.",13,Brushes.White,FontWeights.Normal);notes.TextWrapping=TextWrapping.Wrap;notes.Margin=new Thickness(0,10,0,18);side.Children.Add(notes);
   rollback=Button("Restore previous build",false);rollback.HorizontalAlignment=HorizontalAlignment.Left;rollback.Click+=async(s,e)=>{if(MessageBox.Show("Restore the previous game build? Your co-op server may require the newest build. Saved progress will be kept.","IRON SUN",MessageBoxButton.YesNo)==MessageBoxResult.Yes)await Operate("Rollback");};side.Children.Add(rollback);
   var bottom=new Grid{Margin=new Thickness(28,0,28,0),VerticalAlignment=VerticalAlignment.Center};Grid.SetRow(bottom,2);root.Children.Add(bottom);
   var footer=Text("WINDOWS 64-BIT  ·  LAUNCHER "+Settings.LauncherVersion,10,Muted,FontWeights.Normal);bottom.Children.Add(footer);
   var website=Button("Playtest guide  ↗",false);website.HorizontalAlignment=HorizontalAlignment.Right;website.Click+=(s,e)=>Process.Start(new ProcessStartInfo(Settings.Website){UseShellExecute=true});bottom.Children.Add(website);
   Loaded+=async(s,e)=>{
    if(TestSnapshot!=null){status.Text="Ready to install the latest playtest.";version.Text="Latest game: PLAYTEST / VS58";notes.Text="Private co-op server\nTwo weapon slots\nArena collision reliability";primary.Content="Install IRON SUN";await Task.Delay(350);Snapshot(TestSnapshot);Close();return;}
    busy=true;SetButtons();
    try {status.Text="Checking launcher updates...";if(await Program.UpdateLauncher()){busy=false;Application.Current.Shutdown();return;}}
    catch(Exception ex){status.Text=ex.Message;busy=false;SetButtons();return;}
    busy=false;RefreshInstalled();await Operate(installed?"Update":"Check");
   };
   var timer=new DispatcherTimer{Interval=TimeSpan.FromMinutes(10)};timer.Tick+=async(s,e)=>{if(!busy&&!Settings.GameRunning())await Operate(installed?"Update":"Check");};timer.Start();
   Closing+=(s,e)=>{if(busy){e.Cancel=true;status.Text="An update is running. Let it finish before closing the launcher.";}};
  }
  TextBlock Text(string value,double size,Brush color,FontWeight weight) {return new TextBlock{Text=value,FontSize=size,Foreground=color,FontWeight=weight,VerticalAlignment=VerticalAlignment.Center};}
  Button Button(string value,bool important) {
   var b=new Button{Content=value,FontSize=13,Padding=new Thickness(12,8,12,8),Background=important?Amber:new SolidColorBrush(Color.FromRgb(31,36,35)),Foreground=important?new SolidColorBrush(Color.FromRgb(20,22,20)):Brushes.White,BorderThickness=new Thickness(0),Cursor=Cursors.Hand,FontWeight=important?FontWeights.SemiBold:FontWeights.Normal};
   AutomationProperties.SetName(b,value);return b;
  }
  void RefreshInstalled() {
   var record=System.IO.Path.Combine(Settings.Root,"Game","installed.json");installed=File.Exists(record);
   if(installed) {
    try {var m=Settings.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(record));version.Text="Installed: "+Settings.GetString(m,"version");}
    catch {version.Text="Install record needs repair.";installed=false;}
   } else version.Text="No game installed yet.";
   currentAction=installed?"Play":"Install";primary.Content=installed?"Play IRON SUN":"Install IRON SUN";SetButtons();
  }
  void SetButtons() {
   bool running=Settings.GameRunning();primary.IsEnabled=!busy&&!running;check.IsEnabled=!busy&&!running;repair.IsEnabled=!busy&&installed&&!running;rollback.IsEnabled=!busy&&Directory.Exists(System.IO.Path.Combine(Settings.Root,"Previous"))&&!running;
   if(running)status.Text="IRON SUN is running. Updates wait until you close the game.";
  }
  async Task Operate(string action) {
   if(busy)return;
   if(action!="Check"&&Settings.GameRunning()){status.Text="Close IRON SUN before updating.";SetButtons();return;}
   busy=true;SetButtons();progress.Visibility=Visibility.Visible;progress.IsIndeterminate=true;download.Text="";
   try {
    var result=await Program.RunEngine(action,item=>Dispatcher.BeginInvoke(new Action(()=>{
     string kind=Settings.GetString(item,"type");
     if(kind=="status"){status.Text=Settings.GetString(item,"message");progress.IsIndeterminate=true;}
     if(kind=="progress"){progress.IsIndeterminate=false;progress.Value=Convert.ToDouble(item["percent"]);download.Text=Convert.ToInt64(item["bytes"])/1048576+" MiB downloaded  /  "+item["percent"]+"%";}
    })));
    string code=Settings.GetString(result,"status");string release=Settings.GetString(result,"release_notes");if(release.Length>0)notes.Text=release;
    if(code=="AVAILABLE") {version.Text="Latest: PLAYTEST / VS"+Settings.GetString(result,"protocol");status.Text="Ready to install IRON SUN.";download.Text="Game download: "+(Convert.ToInt64(result["archive_size"])/1048576)+" MiB";}
    else if(code=="OFFLINE_CURRENT")status.Text=Settings.GetString(result,"warning");
    else if(code=="ROLLBACK_HELD"||code=="ROLLED_BACK")status.Text="Previous build restored. Co-op may need the newest build; Repair installs the current release.";
    else status.Text=code=="REPAIRED"?"Game files repaired. Ready to play.":code=="UPDATED"?"Updated. Ready for your next run.":"You're up to date. Ready to play.";
    RefreshInstalled();
   } catch(Exception ex) {status.Text=ex.Message;RefreshInstalled();}
   finally {busy=false;progress.Visibility=Visibility.Collapsed;SetButtons();}
  }
  void LaunchGame() {
   try {
    string folder=System.IO.Path.Combine(Settings.Root,"Game","Windows");Settings.EnsurePlain(folder);
    string exe=System.IO.Path.Combine(folder,"TP_FirstPerson.exe");
    Process.Start(new ProcessStartInfo(exe,"/Game/Variant_Shooter/Lvl_Shooter?RidgefireMenu"){WorkingDirectory=folder,UseShellExecute=true});status.Text="Starting IRON SUN...";
    var poll=new DispatcherTimer{Interval=TimeSpan.FromSeconds(2)};poll.Tick+=(s,e)=>{SetButtons();if(!Settings.GameRunning()){poll.Stop();status.Text="Ready for your next run.";}};poll.Start();
   } catch(Exception ex){status.Text=ex.Message;}
  }
  void Snapshot(string path) {
   UpdateLayout();var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(this);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(path))encoder.Save(stream);
  }
 }
}
