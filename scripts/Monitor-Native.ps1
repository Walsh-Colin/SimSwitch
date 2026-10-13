Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MonitorSwitch {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct Device {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string description;
        public int flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string key;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode, Size=220)]
    public struct Mode {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string deviceName;
        public ushort specVersion;
        public ushort driverVersion;
        public ushort size;
        public ushort driverExtra;
        public uint fields;
        public int x;
        public int y;
        public uint orientation;
        public uint fixedOutput;
        public short color;
        public short duplex;
        public short yResolution;
        public short ttOption;
        public short collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string formName;
        public ushort logPixels;
        public uint bitsPerPixel;
        public uint width;
        public uint height;
        public uint displayFlags;
        public uint frequency;
        public uint icmMethod;
        public uint icmIntent;
        public uint mediaType;
        public uint ditherType;
        public uint reserved1;
        public uint reserved2;
        public uint panningWidth;
        public uint panningHeight;
    }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string name, uint index, ref Device device, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string name, int index, ref Mode mode);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(string name, ref Mode mode, IntPtr hwnd, uint flags, IntPtr param);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")]
    public static extern int Apply(string name, IntPtr mode, IntPtr hwnd, uint flags, IntPtr param);
    public static Device[] Devices() {
        var devices = new System.Collections.Generic.List<Device>();
        for (uint i = 0; ; i++) {
            Device device = new Device();
            device.cb = Marshal.SizeOf(typeof(Device));
            if (!EnumDisplayDevices(null, i, ref device, 0)) break;
            if ((device.flags & 8) == 0) devices.Add(device);
        }
        return devices.ToArray();
    }
    public static int ApplyAll() {
        return Apply(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
    }
    public static Mode[] Modes(string name) {
        var modes = new System.Collections.Generic.List<Mode>();
        for (int i = 0; ; i++) {
            Mode mode = new Mode(); mode.size = 220;
            if (!EnumDisplaySettings(name, i, ref mode)) break;
            if (mode.width > 0 && mode.height > 0 && mode.bitsPerPixel == 32)
                modes.Add(mode);
        }
        return modes.ToArray();
    }
    public static Mode Read(string name, int index) {
        Mode mode = new Mode(); mode.size = 220;
        if (!EnumDisplaySettings(name, index, ref mode))
            throw new Exception("Cannot read display settings for " + name);
        return mode;
    }
    public static Mode Resolve(string name, uint width, uint height, uint hz, uint orientation, uint displayFlags) {
        // Retain the complete driver-returned structure, including fields not
        // represented in JSON, instead of constructing a mostly empty DEVMODE.
        Mode current = new Mode(); current.size = 220;
        if (EnumDisplaySettings(name, -1, ref current) &&
            current.width == width && current.height == height && current.frequency == hz &&
            current.orientation == orientation && current.displayFlags == displayFlags)
            return current;
        foreach (Mode mode in Modes(name)) {
            if (mode.width == width && mode.height == height && mode.frequency == hz &&
                mode.orientation == orientation && mode.displayFlags == displayFlags)
                return mode;
        }
        throw new Exception("No driver-supported mode for " + name + ": " + width + "x" + height + " @ " + hz + " Hz. Refresh monitor settings.");
    }
}
'@
