/* process.vala
 *
 * Copyright (C) 2020 Ivan Molodetskikh
 * Copyright (C) 2017 Red Hat, Inc.
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
 *
 * Authors: Petr Štětka <pstetka@redhat.com>
 */
using Gee;

namespace BxtLauncher
{
    public class Process : Object
    {
        public Pid pid { get; private set; }
        public string cmdline { get; private set; }
        public uint uid { get; private set; }
        public uint64 start_time { get; set; default = 0; }

        public Process(Pid pid)
        {
            this.pid = pid;
            this.cmdline = get_full_process_cmd (pid);
            this.uid = _get_uid ();
            this.start_time = _get_start_time ();
        }

        private uint _get_uid()
        {
            GTop.ProcUid procUid;
            GTop.get_proc_uid(out procUid, pid);
            return procUid.uid;
        }

        private uint64 _get_start_time()
        {
            GTop.ProcTime proc_time;
            GTop.get_proc_time (out proc_time, pid);
            return proc_time.start_time;
        }

        public HashMap<string, string> get_env () throws Error
        {
            var file = File.new_for_path (@"/proc/$pid/environ");
            var env = new HashMap<string, string> ();

            uint8[] data;
            string etag_out;
            file.load_contents (null, out data, out etag_out);

            var start = 0;
            for (int i = 0; i < data.length; i++) {
                if (data[i] == 0) {
                    var v = (string) data[start:i];
                    var kv = v.split ("=", 2);
                    env[kv[0]] = kv[1];
                    start = i + 1;
                }
            }

            return env;
        }

        /* static pid related methods */
        public static string get_full_process_cmd (Pid pid) {
            GTop.ProcArgs proc_args;
            GTop.ProcState proc_state;
            string[] args = GTop.get_proc_argv (out proc_args, pid, 0);
            GTop.get_proc_state (out proc_state, pid);
            string cmd = (string) proc_state.cmd;

            /* cmd is most likely a truncated version, therefore
             * we check the first two arguments of the full argv
             * vector if they match cmd and if so, use that */
            for (int i = 0; i < 2; i++) {
                if (args[i] == null)
                    continue;

                /* TODO: this will fail if args[i] is a commandline,
                 * i.e. composed of multiple segments and one of the
                 * later ones is a unix path */
                var name = Path.get_basename (args[i]);
                if (!name.has_prefix (cmd))
                    continue;

                name = Process.first_component (name);
                return Process.sanitize_name (name);
            }

            return Process.sanitize_name (cmd);
        }

        /* static utility methods */
        public static string? sanitize_name (string name) {
            string? result = null;

            if (name == null)
                return null;

            try {
                var rgx = new Regex ("[^a-zA-Z0-9._-]");
                result = rgx.replace (name, name.length, 0, "");
            } catch (RegexError e) {
                warning ("Unable to sanitize name: %s", e.message);
            }

            return result;
        }

        public static string first_component (string str) {

            for (int i = 0; i < str.length; i++) {
                if (str[i] == ' ') {
                    return str.substring(0, i);
                }
            }

            return str;
        }
    }
}
