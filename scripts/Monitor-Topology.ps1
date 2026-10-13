Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class MonitorTopology {
    public static string LastStage;
    static int ComparePaths(Path a, Path b) {
        int active=((b.Flags&1)!=0).CompareTo((a.Flags&1)!=0);
        if (active!=0) return active;
        int source=a.Source.Id.CompareTo(b.Source.Id);
        return source!=0 ? source : a.Target.Id.CompareTo(b.Target.Id);
    }
    [StructLayout(LayoutKind.Sequential)] public struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] public struct Rational { public uint Num, Den; }
    [StructLayout(LayoutKind.Sequential)] public struct Signal {
        public ulong PixelRate; public Rational HSync, VSync;
        public uint ActiveWidth, ActiveHeight, TotalWidth, TotalHeight, Standard, Scanline;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Source { public Luid Adapter; public uint Id, Mode, Status; }
    [StructLayout(LayoutKind.Sequential)] public struct Target {
        public Luid Adapter; public uint Id, Mode, Technology, Rotation, Scaling;
        public Rational Refresh; public uint Scanline; public int Available; public uint Status;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Path { public Source Source; public Target Target; public uint Flags; }
    [StructLayout(LayoutKind.Explicit, Size=64)] public struct Mode {
        [FieldOffset(0)] public uint Type;
        [FieldOffset(4)] public uint Id;
        [FieldOffset(8)] public Luid Adapter;
        [FieldOffset(16)] public uint Width;
        [FieldOffset(16)] public Signal Signal;
        [FieldOffset(20)] public uint Height;
        [FieldOffset(24)] public uint PixelFormat;
        [FieldOffset(28)] public int X;
        [FieldOffset(32)] public int Y;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct SourceName {
        public uint Type, Size; public Luid Adapter; public uint Id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
    }
    public struct Request { public string Name, Identity; public uint Width, Height, Hz; public int X,Y; public bool Primary; }
    public struct Mapping { public string Name, Identity, LegacyIdentity; public uint Width,Height,Hz; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct TargetName {
        public uint Type,Size; public Luid Adapter; public uint Id,Flags,Technology;
        public ushort Manufacturer,Product; public uint Connector;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=64)] public string Friendly;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DevicePath;
    }
    [DllImport("user32.dll",EntryPoint="DisplayConfigGetDeviceInfo")] static extern int GetTargetName(ref TargetName packet);
    [StructLayout(LayoutKind.Sequential)] public struct Preferred {
        public uint Type,Size; public Luid Adapter; public uint Id,Width,Height; public Signal Signal;
    }
    [DllImport("user32.dll",EntryPoint="DisplayConfigGetDeviceInfo")] static extern int GetPreferred(ref Preferred packet);
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] Path[] pathArray, ref uint modes, [Out] Mode[] modeArray, IntPtr topology);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);
    [DllImport("user32.dll")] static extern int SetDisplayConfig(uint paths, [In] Path[] pathArray, uint modes, [In] Mode[] modeArray, uint flags);
    static string Name(Source source) {
        SourceName packet = new SourceName(); packet.Type=1; packet.Size=(uint)Marshal.SizeOf(typeof(SourceName));
        packet.Adapter=source.Adapter; packet.Id=source.Id;
        int code=DisplayConfigGetDeviceInfo(ref packet);
        if (code!=0) throw new Exception("DisplayConfigGetDeviceInfo failed (code " + code + ").");
        return packet.Name;
    }
    static string LegacyIdentity(Target target) { return target.Adapter.High+":"+target.Adapter.Low+":"+target.Id; }
    static string Identity(Target target) {
        TargetName packet=new TargetName(); packet.Type=2; packet.Size=(uint)Marshal.SizeOf(typeof(TargetName));
        packet.Adapter=target.Adapter; packet.Id=target.Id;
        if (GetTargetName(ref packet)==0 && !String.IsNullOrEmpty(packet.DevicePath)) return packet.DevicePath.ToUpperInvariant();
        return LegacyIdentity(target);
    }
    public static Mapping[] Mappings() {
        uint pc,mc; int code=GetDisplayConfigBufferSizes(1,out pc,out mc);
        if (code!=0) throw new Exception("Display identity query failed (code " + code + ").");
        Path[] paths=new Path[pc]; Mode[] modes=new Mode[mc];
        code=QueryDisplayConfig(1,ref pc,paths,ref mc,modes,IntPtr.Zero);
        if (code==122) return Mappings();
        if (code!=0) throw new Exception("Display identity query failed (code " + code + ").");
        Array.Sort(paths,0,(int)pc,Comparer<Path>.Create(ComparePaths));
        var result=new List<Mapping>(); var names=new HashSet<string>(); var targets=new HashSet<string>();
        for (int i=0;i<pc;i++) {
            Path path=paths[i]; if (path.Target.Available==0) continue;
            string name=Name(path.Source), key=Identity(path.Target);
            if (names.Contains(name) || targets.Contains(key)) continue;
            names.Add(name); targets.Add(key);
            Preferred preferred=new Preferred(); preferred.Type=3; preferred.Size=(uint)Marshal.SizeOf(typeof(Preferred));
            preferred.Adapter=path.Target.Adapter; preferred.Id=path.Target.Id;
            int preferredCode=GetPreferred(ref preferred);
            uint hz=preferredCode==0 && preferred.Signal.VSync.Den>0 ? (uint)Math.Round((double)preferred.Signal.VSync.Num/preferred.Signal.VSync.Den) : 0;
            result.Add(new Mapping {Name=name,Identity=key,LegacyIdentity=LegacyIdentity(path.Target),Width=preferred.Width,Height=preferred.Height,Hz=hz});
        }
        return result.ToArray();
    }
    public static int Configure(Request[] requests, bool validate) {
        uint pathCount=0, modeCount=0;
        Path[] allPaths=null; Mode[] allModes=null;
        int code=0;
        for (int attempt=0; attempt<5; attempt++) {
            LastStage="GetDisplayConfigBufferSizes";
            code=GetDisplayConfigBufferSizes(1,out pathCount,out modeCount);
            if (code!=0) return code;
            allPaths=new Path[pathCount]; allModes=new Mode[modeCount];
            LastStage="QueryDisplayConfig";
            code=QueryDisplayConfig(1,ref pathCount,allPaths,ref modeCount,allModes,IntPtr.Zero);
            if (code!=122) break;
        }
        if (code!=0) return code;
        var chosen=new List<Path>(); var modes=new List<Mode>();
        var targets=new HashSet<string>(); var sources=new HashSet<string>();
        // Prefer the currently active route for each GDI device.
        Array.Sort(allPaths,0,(int)pathCount,Comparer<Path>.Create(ComparePaths));
        foreach (Request request in requests) {
            bool found=false;
            for (int i=0;i<pathCount;i++) {
                Path path=allPaths[i];
                if (path.Target.Available==0) continue;
                if (!String.IsNullOrEmpty(request.Identity)) {
                    if (Identity(path.Target)!=request.Identity && LegacyIdentity(path.Target)!=request.Identity) continue;
                } else if (!String.Equals(Name(path.Source),request.Name,StringComparison.OrdinalIgnoreCase)) continue;
                string target=path.Target.Adapter.High+":"+path.Target.Adapter.Low+":"+path.Target.Id;
                string source=path.Source.Adapter.High+":"+path.Source.Adapter.Low+":"+path.Source.Id;
                if (targets.Contains(target) || sources.Contains(source)) continue;
                targets.Add(target); sources.Add(source);
                Mode mode=new Mode(); mode.Type=1; mode.Id=path.Source.Id; mode.Adapter=path.Source.Adapter;
                mode.Width=request.Width; mode.Height=request.Height; mode.PixelFormat=4; mode.X=request.X; mode.Y=request.Y;
                uint previousSource=path.Source.Mode, previousTarget=path.Target.Mode;
                path.Source.Mode=(uint)modes.Count; path.Source.Status=0;
                modes.Add(mode);
                path.Target.Mode=UInt32.MaxValue; path.Target.Status=0;
                path.Target.Refresh.Num=request.Hz; path.Target.Refresh.Den=1;
                path.Target.Scanline=0; path.Flags=1;
                if (path.Target.Rotation==0) path.Target.Rotation=1;
                if (path.Target.Scaling==0) path.Target.Scaling=128;
                path.Target.Scanline=1;
                if (previousSource<modeCount && previousTarget<modeCount &&
                    allModes[previousSource].Type==1 && allModes[previousTarget].Type==2 &&
                    allModes[previousSource].Width==request.Width && allModes[previousSource].Height==request.Height) {
                    Mode targetMode=allModes[previousTarget];
                    Rational rate=targetMode.Signal.VSync;
                    if (rate.Den>0 && Math.Abs((double)rate.Num/rate.Den-request.Hz)<1.0) {
                        path.Target.Mode=(uint)modes.Count; modes.Add(targetMode);
                    }
                }
                chosen.Add(path); found=true; break;
            }
            if (!found) throw new Exception("No available display path for " + request.Name + ". Reconnect the monitor and click Refresh.");
        }
        // Source modes specify the entire desktop at once; origin identifies primary.
        LastStage="SetDisplayConfig " + (validate?"validate":"apply");
        return SetDisplayConfig((uint)chosen.Count,chosen.ToArray(),(uint)modes.Count,modes.ToArray(),0x20u|0x400u|(validate?0x40u:(0x80u|0x200u)));
    }
}
'@
