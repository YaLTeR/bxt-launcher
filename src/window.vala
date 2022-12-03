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

        [GtkChild]
        private unowned Gtk.ComboBoxText mod_combo_box;

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
                fatal_error (@"Could not open the settings schema. Make sure the gschemas.compiled file is in the same folder as the launcher.\n\n$(e.message)");
                return;
            }

            detect_mod_folders.begin ();
        }

        private async void detect_mod_folders () {
            var hl_pwd = settings.get_string ("hl-pwd");
            if (hl_pwd == "") {
                return;
            }

            var hl_dir = File.new_for_path (hl_pwd);

            var mod_folders = new HashTable<string, string> (str_hash, str_equal);

            try {
                var enumerator = yield hl_dir.enumerate_children_async (
                    "standard::type,standard::name,standard::display-name",
                    FileQueryInfoFlags.NONE
                );

                while (true) {
                    var files = yield enumerator.next_files_async (100);
                    if (files.length () == 0) {
                        break;
                    }

                    foreach (var file in files) {
                        if (file.get_file_type () != FileType.DIRECTORY) {
                            continue;
                        }

                        string? name;
                        if (yield is_mod_folder (hl_dir.get_child (file.get_name ()), out name)) {
                            mod_folders[file.get_name ()] =
                                (name != null) ? name : file.get_display_name ();
                        }
                    }
                }
            } catch (Error _) {
                // Proceed on any errors, the code below handles this case.
            }

            mod_combo_box.remove_all ();
            if (mod_folders.size () == 0) {
                mod_combo_box.append ("valve", "Half-Life");
                mod_combo_box.append ("gearbox", "Opposing Force");
                mod_combo_box.append ("bshift", "Blue Shift");
                mod_combo_box.set_active_id ("valve");
            } else {
                string? first = null;
                mod_folders.foreach((id, name) => {
                    if (first == null) {
                        first = id;
                    }

                    if (id == "valve") {
                        mod_combo_box.prepend (id, name);
                        first = id;
                    } else {
                        mod_combo_box.append (id, name);
                    }
                });

                mod_combo_box.set_active_id (first);
            }
        }

        private async bool is_mod_folder (File folder, out string? name) {
            name = null;
            var liblist = folder.get_child ("liblist.gam");

            FileInputStream fis;
            try {
                fis = yield liblist.read_async ();
            } catch (Error _) {
                // For example, if liblist.gam does not exist.
                return false;
            }

            try {
                var dis = new DataInputStream (fis);

                string? line;
                while ((line = yield dis.read_line_utf8_async (Priority.DEFAULT, null, null)) != null) {
                    if (line.length < 4 || line[0:4].ascii_casecmp ("game") != 0) {
                        continue;
                    }

                    var first_quote = line.index_of_char ('"');
                    if (first_quote == -1) {
                        break;
                    }

                    var second_quote = line.index_of_char ('"', first_quote + 1);
                    if (second_quote == -1) {
                        break;
                    }

                    name = line[first_quote + 1:second_quote];
                    break;
                }
            } catch (Error _) {
                // If we couldn't get the display name just return true, it'll use the folder name.
            }

            return true;
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

        private void show_error_dialog (string message, string secondary) {
            var dialog = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.ERROR,
                Gtk.ButtonsType.OK,
                message
            );
            dialog.secondary_text = secondary;
            dialog.response.connect ((dialog, response) => dialog.destroy ());
            dialog.show ();
        }

        private void get_hl_environment () {
            var monitor = SystemMonitor.get_default ();

            // Check if Half-Life is already running.
            var hl = monitor.find_process ("hl_linux");
            if (hl != null) {
                var dialog = new Gtk.MessageDialog (
                    this,
                    Gtk.DialogFlags.DESTROY_WITH_PARENT,
                    Gtk.MessageType.INFO,
                    Gtk.ButtonsType.OK_CANCEL,
                    "Half-Life is Already Running"
                );
                dialog.secondary_text = "Half-Life will be closed and started again.";
                var response = dialog.run ();
                dialog.destroy ();

                if (response == Gtk.ResponseType.OK) {
                    extract_environment_and_launch_hl (hl);
                }

                return;
            }

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
                show_error_dialog (
                    "Failed to Run Half-Life",
                    @"Make sure that Steam is installed.\n\n$(e.message)"
                );
                return;
            }

            // Spawn a dialog to let the user know what's happening.
            dialog = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.INFO,
                Gtk.ButtonsType.CANCEL,
                "Configuring Launch Parameters"
            );
            dialog.secondary_text = "Half-Life will open and then close.";
            dialog.response.connect (close_dialog);
            dialog.show ();
        }

        private void process_added_cb (SystemMonitor monitor, Process process) {
            if (process.cmdline == "hl_linux") {
                monitor.on_process_added.disconnect (process_added_cb);

                extract_environment_and_launch_hl (process);
            }
        }

        private void extract_environment_and_launch_hl (Process process)
            requires (process.cmdline == "hl_linux")
        {
            string hl_pwd = "";

            try {
                var env = process.get_env ();

                if (!env.contains ("PWD")) {
                    close_dialog ();

                    show_error_dialog (
                        "Failed to Configure Launch Parameters",
                        "Half-Life environment doesn't contain PWD."
                    );
                } else {
                    hl_pwd = env["PWD"];
                    settings.set_string ("hl-pwd", hl_pwd);
                    settings.set_string ("hl-ld-library-path", env["LD_LIBRARY_PATH"]);
                    settings.set_string ("hl-ld-preload", env["LD_PRELOAD"]);

                    var monitor = SystemMonitor.get_default ();
                    monitor.on_process_removed.connect (process_removed_cb);
                }
            } catch (Error e) {
                close_dialog ();

                show_error_dialog (
                    "Failed to Configure Launch Parameters",
                    @"Could not read the Half-Life environment.\n\n$(e.message)"
                );
            }

            // Close this Half-Life instance.
#if VALA_0_40
            var sigterm = Posix.Signal.TERM;
#else
            var sigterm = Posix.SIGTERM;
#endif
            Posix.kill (process.pid, sigterm);
        }

        private void process_removed_cb (SystemMonitor monitor, Process process) {
            if (process.cmdline == "hl_linux") {
                monitor.on_process_removed.disconnect (process_removed_cb);

                close_dialog ();

                var hl_pwd = settings.get_string ("hl-pwd");
                if (hl_pwd != "") {
                    launch_hl (hl_pwd);

                    // Update mod folders afterwards because it resets the selected mod.
                    detect_mod_folders.begin ();
                }
            }
        }

        private void launch_hl (string hl_pwd)
            requires (bxt_path != null)
            requires (hl_pwd != "")
        {
            // Check that libBunnymodXT.so is present.
            var bxt = File.new_for_path (bxt_path);
            if (!bxt.query_exists ()) {
                show_error_dialog (
                    "Bunnymod XT is Missing",
                    @"Make sure that libBunnymodXT.so is in the same folder as the launcher: $(Path.get_dirname (bxt_path))"
                );
                return;
            }

            string[] spawn_args = {"./hl_linux", "-steam", "-game", mod_combo_box.get_active_id ()};
            string[] spawn_env = Environ.get ();

            var hl_ld_library_path = settings.get_string ("hl-ld-library-path");

            // Add BXT in the end: gameoverlayrenderer really doesn't like being after BXT.
            var ld_preload = "";
            // TODO: gameoverlayrenderer seems to override dlsym(), which prevents BXT from doing
            // the same, which results in some mod client libraries not being hooked (notably, the
            // Opposing Force one). So, don't use the Steam LD_PRELOAD until this is resolved in
            // BXT.
            //
            // var hl_ld_preload = settings.get_string ("hl-ld-preload");
            // if (hl_ld_preload != "") {
            //     ld_preload += @"$hl_ld_preload:";
            // }
            ld_preload += bxt_path;

            bool found_pwd = false, found_ld_library_path = false, found_ld_preload = false, found_steam_env = false;
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

                if (v.has_prefix ("SteamEnv=")) {
                    found_steam_env = true;
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
            if (!found_steam_env) {
                spawn_env += @"SteamEnv=1";
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
                show_error_dialog (
                    "Failed to Run Half-Life",
                    @"Please try again. The launch parameters will be re-configured.\n\n$(e.message)"
                );

                // Resetting hl-pwd triggers the re-configure.
                settings.set_string ("hl-pwd", "");

                return;
            }
        }
    }
}
