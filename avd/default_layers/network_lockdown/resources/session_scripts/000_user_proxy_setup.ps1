$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# Set the proxy server
Set-ItemProperty -Path $regPath -Name "AutoConfigURL" -Value "http://localhost:2015/proxy.pac"
# Enable the proxy
Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
Set-ItemProperty -Path $regPath -Name AutoDetect -Value 0

# Refresh the settings
$refreshSystem = @"
using System;
using System.Runtime.InteropServices;

public class RefreshSystem
{
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);

    public const int INTERNET_OPTION_SETTINGS_CHANGED = 39;
    public const int INTERNET_OPTION_REFRESH = 37;

    public static void Refresh()
    {
        InternetSetOption(IntPtr.Zero, INTERNET_OPTION_SETTINGS_CHANGED, IntPtr.Zero, 0);
        InternetSetOption(IntPtr.Zero, INTERNET_OPTION_REFRESH, IntPtr.Zero, 0);
    }
}
"@
Add-Type -TypeDefinition $refreshSystem
[RefreshSystem]::Refresh()

Write-Output "Proxy server set to $proxyIpAddr and enabled."