/* window.vala
 *
 * Copyright 2020 Ivan Molodetskikh
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
namespace BxtLauncher {
    [GtkTemplate (ui = "/yalter/BxtLauncher/window.ui")]
    public class Window : Gtk.ApplicationWindow {
        private Settings settings;

        private string? bxt_path { get; set; }

        private Gtk.MessageDialog? dialog { get; set; }

        public Window (Gtk.Application app) {
            Object (application: app);

            settings = null;
            bxt_path = null;
            dialog = null;

            string path;
            try {
                path = FileUtils.read_link ("/proc/self/exe");
            } catch (FileError e) {
                fatal_error (@"Could not get the launcher executable path.\n\n$(e.message)");
                return;
            }

            path = Path.get_dirname (path);
            bxt_path = Path.build_filename (path, "libBunnymodXT.so");

            try {
                var source = new SettingsSchemaSource.from_directory (path, null, false);
                var schema = source.lookup ("yalter.BxtLauncher", false);
                settings = new Settings.full (schema, null, null);
            } catch (Error e) {
                print ("Error opening schema: %s\n", e.message);
            }
        }

        [GtkCallback]
        private void launch_button_clicked_cb (Gtk.Button button) {
            var hl_pwd = settings.get_string ("hl-pwd");

            if (hl_pwd == "") {
                get_hl_environment ();
            } else {
                launch_hl (hl_pwd);
            }
        }

        private void close_dialog () {
            if (dialog == null)
                return;

            dialog.destroy ();
            dialog = null;
        }

        private void fatal_error (string message) {
            var dialog = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.ERROR,
                Gtk.ButtonsType.OK,
                "Fatal Error"
            );
            dialog.secondary_text = message;
            dialog.run ();
            application.quit ();
        }

        private void get_hl_environment () {
            // Spawn a dialog to let the user know what's happening.
            dialog = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.INFO,
                Gtk.ButtonsType.CANCEL,
                "Configuring Launch Options"
            );
            dialog.secondary_text = "Half-Life will open and then close.";
            dialog.response.connect (close_dialog);
            dialog.show ();

            var monitor = SystemMonitor.get_default ();
            monitor.on_process_added.connect (process_added_cb);

            try {
                string[] spawn_args = {"steam", "steam://rungameid/70"};

                GLib.Process.spawn_async (
                    null,
                    spawn_args,
                    null,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    null
                );
            } catch (SpawnError e) {
                print ("Error: %s\n", e.message);
            }
        }

        private void process_added_cb (SystemMonitor monitor, Process process) {
            if (process.cmdline == "hl_linux") {
                monitor.on_process_added.disconnect (process_added_cb);

                string hl_pwd = "";

                try {
                    var env = process.get_env ();

                    if (!env.has_key ("PWD")) {
                        print ("Half-Life environment doesn't have PWD\n");
                    } else {
                        hl_pwd = env["PWD"];
                        settings.set_string ("hl-pwd", hl_pwd);
                        settings.set_string ("hl-ld-library-path", env["LD_LIBRARY_PATH"]);
                        settings.set_string ("hl-ld-preload", env["LD_PRELOAD"]);
                    }
                } catch (Error e) {
                    print ("Couldn't read the Half-Life environment: %s", e.message);
                }

                // Close this Half-Life instance.
#if VALA_0_40
                var sigterm = Posix.Signal.TERM;
#else
                var sigterm = Posix.SIGTERM;
#endif
                Posix.kill (process.pid, sigterm);

                monitor.on_process_removed.connect (process_removed_cb);
            }
        }

        private void process_removed_cb (SystemMonitor monitor, Process process) {
            if (process.cmdline == "hl_linux") {
                monitor.on_process_removed.disconnect (process_removed_cb);

                close_dialog ();

                var hl_pwd = settings.get_string ("hl-pwd");
                if (hl_pwd != "") {
                    launch_hl (hl_pwd);
                }
            }
        }

        private void launch_hl (string hl_pwd)
            requires (bxt_path != null)
            requires (hl_pwd != "")
        {
            string[] spawn_args = {"./hl_linux", "-steam"};
            string[] spawn_env = Environ.get ();

            var hl_ld_library_path = settings.get_string ("hl-ld-library-path");
            var hl_ld_preload = settings.get_string ("hl-ld-preload");

            // Add BXT in the end: gameoverlayrenderer really doesn't like being after BXT.
            var ld_preload = "";
            if (hl_ld_preload != "") {
                ld_preload += @"$hl_ld_preload:";
            }
            ld_preload += bxt_path;

            bool found_pwd = false, found_ld_library_path = false, found_ld_preload = false;
            for (int i = 0; i < spawn_env.length; i++) {
                var v = spawn_env[i];

                if (v.has_prefix ("PWD=")) {
                    found_pwd = true;
                    spawn_env[i] = @"PWD=$hl_pwd";
                }

                if (v.has_prefix ("LD_LIBRARY_PATH=")) {
                    found_ld_library_path = true;
                    if (hl_ld_library_path != "") {
                        spawn_env[i] = @"LD_LIBRARY_PATH=$hl_ld_library_path";
                    }
                }

                if (v.has_prefix ("LD_PRELOAD=")) {
                    found_ld_preload = true;
                    spawn_env[i] = @"LD_PRELOAD=$ld_preload";
                }
            }

            if (!found_pwd) {
                spawn_env += @"PWD=$hl_pwd";
            }
            if (!found_ld_library_path && hl_ld_library_path != "") {
                spawn_env += @"LD_LIBRARY_PATH=$hl_ld_library_path";
            }
            if (!found_ld_preload) {
                spawn_env += @"LD_PRELOAD=$ld_preload";
            }

            debug (@"Spawning:\n\tworking_directory = $hl_pwd\n\targv = $(string.joinv(", ", spawn_args))\n\tenvp =\n\t\t$(string.joinv("\n\t\t", spawn_env))\n");

            try {
                GLib.Process.spawn_async (
                    hl_pwd,
                    spawn_args,
                    spawn_env,
                    0,
                    null,
                    null
                );
            } catch (SpawnError e) {
                print ("Error: %s\n", e.message);
            }
        }
    }
}
