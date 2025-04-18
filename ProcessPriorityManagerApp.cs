using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

namespace ProcessPriorityManager
{
    public class ProcessPriorityManagerApp : Form
    {
        private NotifyIcon trayIcon;
        private ContextMenuStrip trayMenu;
        private System.Threading.Timer monitorTimer;
        private bool isMonitoring = false;
        private HashSet<int> processedIds = new HashSet<int>();

        public ProcessPriorityManagerApp()
        {
            // Create tray menu
            trayMenu = new ContextMenuStrip();
            trayMenu.Items.Add("Start Monitoring", null, OnStartMonitoring);
            trayMenu.Items.Add("Stop Monitoring", null, OnStopMonitoring);
            trayMenu.Items.Add("-");
            trayMenu.Items.Add("Exit", null, OnExit);

            // Create tray icon
            trayIcon = new NotifyIcon();
            trayIcon.Text = "Process Priority Manager";
            trayIcon.Icon = SystemIcons.Application;
            trayIcon.ContextMenuStrip = trayMenu;
            trayIcon.Visible = true;

            // Set initial state
            UpdateMenuState(false);

            // Hide form from taskbar
            this.ShowInTaskbar = false;
            this.WindowState = FormWindowState.Minimized;
            this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
            this.Load += (s, e) => this.Hide();
        }

        private void UpdateMenuState(bool isRunning)
        {
            trayMenu.Items[0].Enabled = !isRunning;  // Start
            trayMenu.Items[1].Enabled = isRunning;   // Stop

            if (isRunning)
            {
                trayIcon.Text = "Process Priority Manager (Running)";
                trayIcon.Icon = SystemIcons.Application;
            }
            else
            {
                trayIcon.Text = "Process Priority Manager (Stopped)";
                trayIcon.Icon = SystemIcons.Information;
            }
        }

        private void OnStartMonitoring(object sender, EventArgs e)
        {
            if (!isMonitoring)
            {
                isMonitoring = true;
                UpdateMenuState(true);

                // Show notification
                trayIcon.ShowBalloonTip(
                    3000,
                    "Process Priority Manager",
                    "Monitoring started. PowerShell and Console processes will be set to Realtime priority.",
                    ToolTipIcon.Info
                );

                // Start monitoring timer (check every 2 seconds)
                monitorTimer = new System.Threading.Timer(
                    MonitorProcesses,
                    null,
                    0,
                    2000
                );
            }
        }

        private void OnStopMonitoring(object sender, EventArgs e)
        {
            if (isMonitoring)
            {
                isMonitoring = false;
                UpdateMenuState(false);

                // Stop timer
                monitorTimer?.Dispose();
                monitorTimer = null;

                // Show notification
                trayIcon.ShowBalloonTip(
                    3000,
                    "Process Priority Manager",
                    "Monitoring stopped.",
                    ToolTipIcon.Info
                );
            }
        }

        private void OnExit(object sender, EventArgs e)
        {
            // Clean up
            monitorTimer?.Dispose();
            trayIcon.Visible = false;
            Application.Exit();
        }

        private void MonitorProcesses(object state)
        {
            try
            {
                // Get target processes
                var targetProcessNames = new[] { "powershell", "powershell_ise", "pwsh", "OpenConsole", "WindowsTerminal" };

                foreach (var processName in targetProcessNames)
                {
                    try
                    {
                        var processes = Process.GetProcessesByName(processName);

                        foreach (var process in processes)
                        {
                            // Check if we've already processed this ID
                            if (!processedIds.Contains(process.Id))
                            {
                                try
                                {
                                    // Set priority to Realtime
                                    if (!process.HasExited)
                                    {
                                        process.PriorityClass = ProcessPriorityClass.RealTime;
                                        processedIds.Add(process.Id);

                                        // Log to console (for debugging)
                                        Console.WriteLine($"Set priority for {process.ProcessName} (ID: {process.Id}) to Realtime");
                                    }
                                }
                                catch (Exception ex)
                                {
                                    Console.WriteLine($"Error setting priority for {process.ProcessName} (ID: {process.Id}): {ex.Message}");
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Error getting processes by name {processName}: {ex.Message}");
                    }
                }

                // Clean up processed IDs for processes that no longer exist
                var runningProcesses = Process.GetProcesses();
                var runningIds = new HashSet<int>();

                foreach (var process in runningProcesses)
                {
                    runningIds.Add(process.Id);
                }

                var idsToRemove = new List<int>();
                foreach (var id in processedIds)
                {
                    if (!runningIds.Contains(id))
                    {
                        idsToRemove.Add(id);
                    }
                }

                foreach (var id in idsToRemove)
                {
                    processedIds.Remove(id);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in monitoring timer: {ex.Message}");
            }
        }

        // Check if running as administrator
        private static bool IsAdministrator()
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        [STAThread]
        public static void Main()
        {
            // Check for administrator privileges
            if (!IsAdministrator())
            {
                // Restart as administrator
                var startInfo = new ProcessStartInfo
                {
                    FileName = Application.ExecutablePath,
                    UseShellExecute = true,
                    Verb = "runas"
                };

                try
                {
                    Process.Start(startInfo);
                    return; // Exit this instance
                }
                catch (Exception ex)
                {
                    MessageBox.Show("This application requires administrator privileges to set process priority to Realtime.\n\nError: " + ex.Message,
                        "Administrator Privileges Required", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }

                return; // Exit if we couldn't restart with admin rights
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new ProcessPriorityManagerApp());
        }
    }
}
