/* system-monitor.vala
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

namespace BxtLauncher
{
    public class SystemMonitor : Object
    {
        const int UPDATE_INTERVAL = 1000;

        private HashTable<GLib.Pid, Process> process_table;
        private int process_mode = GTop.KERN_PROC_ALL;
        private static SystemMonitor system_monitor;

        public signal void on_process_added (Process process);
        public signal void on_process_removed (Process process);

        public static SystemMonitor get_default()
        {
            if (system_monitor == null)
                system_monitor = new SystemMonitor ();

            return system_monitor;
        }

        private SystemMonitor()
        {
            GTop.init();

            process_table = new HashTable<GLib.Pid, Process>(direct_hash, direct_equal);

            update_data();
            Timeout.add(UPDATE_INTERVAL, update_data);
        }

        public Process? find_process (string cmdline) {
            return process_table.find ((pid, process) => {
                return process.cmdline == cmdline;
            });
        }

        private bool update_data()
        {
            /* Try to find the difference between the old list of pids,
             * and the new ones, i.e. the one that got added and removed */
            GTop.Proclist proclist;
            var pids = GTop.get_proclist (out proclist, process_mode);
            var old = (ssize_t[]) process_table.get_keys_as_array ();

            size_t new_len = (size_t) proclist.number;
            size_t old_len = process_table.length;

            sort_pids (pids, sizeof (GLib.Pid), new_len);
            sort_pids (old, sizeof (ssize_t), old_len);

            debug ("new_len: %lu, old_len: %lu\n", new_len, old_len);
            uint removed = 0;
            uint added = 0;
            for (size_t i = 0, j = 0; i < new_len || j < old_len; ) {
                uint32 n = i < new_len ? pids[i] : uint32.MAX;
                uint32 o = j < old_len ? (uint32) old[j] : uint32.MAX;

                /* pids: [ 1, 3, 4 ]
                 * old:  [ 1, 2, 4, 5 ] → 2,5 removed, 3 added
                 * i [for pids]: 0  |   1   |   1   |   2  |   3
                 * j [for old]:  0  |   1   |   2   |   2  |   3
                 * n = pids[i]:  1  |   3   |   3   |   4  |  MAX [oob]
                 * o = old[j]:   1  |   2   |   4   |   4  |   5
                 *               =  | n > o | n < o |   =  | n > o
                 * increment:   i,j |   j   |   i   |  i,j |   j
                 * Process op:  chk |  del  |  add  |  chk |  del
                 */

                if (n > o) {
                    /* delete to process not in the new array */
                    Process p = process_table[(GLib.Pid) o];
                    debug ("process removed: %u\n", o);

                    process_removed (p);
                    removed++;

                    j++; /* let o := old[j] catch up */
                } else if (n < o) {
                    /* new process */
                    var p = new Process ((GLib.Pid) n);

                    debug ("process added: %u\n", n);

                    process_added (p);
                    added++;

                    i++; /* let n := pids[i] catch up */
                } else {
                    /* equal pids, might have rolled over though
                     * better check, match start time */
                    Process p = process_table[(GLib.Pid) n];

                    GTop.ProcTime ptime;
                    GTop.get_proc_time (out ptime, p.pid);

                    /* no match: -> old removed, new added */
                    if (ptime.start_time != p.start_time) {
                        debug ("start time mismtach: %u\n", n);
                        process_removed (p);

                        p = new Process ((GLib.Pid) n);
                        process_added (p);
                    }

                    i++; j++; /* both indices move */
                }
            }

            debug ("removed: %u, added: %u\n", removed, added);
            debug ("process table size: %u\n", process_table.length);

            return true;
        }

        private void process_added (Process p) {
            process_table.insert (p.pid, p);
            on_process_added (p);
        }

        private void process_removed (Process p) {
            process_table.remove (p.pid);
            on_process_removed (p);
        }

        public static void sort_pids (void *pids, size_t elm, size_t length)
        {
            Posix.qsort (pids, length, elm, (a, b) => {
                    return (*(GLib.Pid *) a) - (* (GLib.Pid *) b);
                });
        }
    }
}
