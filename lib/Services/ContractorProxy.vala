/***
    Copyright (C) 2011-2013 Lucas Baudin <xapantu@gmail.com>,
                            Akshay Shekher <voldyman666@gmail.com>,
                            Victor Martinez <victoreduardm@gmail.com>

    This program or library is free software; you can redistribute it
    and/or modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 3 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General
    Public License along with this library; if not, write to the
    Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
    Boston, MA 02110-1301 USA.
***/

namespace Granite.Services {
    public interface Contract : Object {
        public abstract string get_display_name ();
        public abstract string get_description ();
        public abstract Icon get_icon ();
        public abstract int execute_with_file (File file) throws Error;
        public abstract int execute_with_files (File[] files) throws Error;
    }

    public errordomain ContractorError {
        SERVICE_NOT_AVAILABLE
    }

    internal struct ContractData {
        string id;
        string display_name;
        string description;
        string icon;
    }

    [DBus (name = "org.elementary.Contractor")]
    internal interface ContractorDBusAPI : Object {
        public abstract ContractData[] list_all_contracts () throws Error;
        public abstract ContractData[] get_contracts_by_mime (string mime_type) throws Error;
        public abstract ContractData[] get_contracts_by_mimelist (string[] mime_types) throws Error;
        public abstract int execute_with_uri (string id, string uri) throws Error;
        public abstract int execute_with_uri_list (string id, string[] uri) throws Error;
    }

    public class ContractorProxy {
        private class GenericContract : Object, Contract {
            private string id;
            private string display_name;
            private string description;
            private string icon_key;

            private Icon icon;

            public GenericContract (ContractData data) {
                icon_key = "";
                update_data (data);
            }

            public void update_data (ContractData data) {
                id = data.id ?? "";
                display_name = data.display_name ?? "";
                description = data.description ?? "";

                if (icon_key != data.icon) {
                    icon_key = data.icon ?? "";
                    icon = null;
                }
            }

            public string get_display_name () {
                return display_name;
            }

            public string get_description () {
                return description;
            }

            public Icon get_icon () {
                if (icon == null) {
                    if (Path.is_absolute (icon_key))
                        icon = new FileIcon (File.new_for_path (icon_key));
                    else
                        icon = new ThemedIcon.with_default_fallbacks (icon_key);
                }

                return icon;
            }

            public int execute_with_file (File file) throws Error {
                return ContractorProxy.execute_with_uri (id, file.get_uri ());
            }

            public int execute_with_files (File[] files) throws Error {
                string[] uris = new string[files.length];

                foreach (var file in files)
                    uris += file.get_uri ();

                return ContractorProxy.execute_with_uri_list (id, uris);
            }
        }


        private static ContractorDBusAPI contractor_dbus;
        private static Gee.HashMap<string, GenericContract> contracts;

        private ContractorProxy () { }

        private static void ensure () throws Error {
            if (contractor_dbus == null) {
                try {
                    contractor_dbus = Bus.get_proxy_sync (BusType.SESSION,
                                                          "org.elementary.Contractor",
                                                          "/org/elementary/contractor");
                } catch (IOError e) {
                    throw new ContractorError.SERVICE_NOT_AVAILABLE (e.message);
                }
            }

            if (contracts == null)
                contracts = new Gee.HashMap<string, GenericContract> ();
        }

        private static int execute_with_uri (string id, string uri) throws Error {
            ensure ();
            return contractor_dbus.execute_with_uri (id, uri);
        }

        private static int execute_with_uri_list (string id, string[] uris) throws Error {
            ensure ();
            return contractor_dbus.execute_with_uri_list (id, uris);
        }

        /**
         * Provides all the contracts.
         *
         * @return List containing all the contracts available in the system.
         */
        public static Gee.List<Contract> get_all_contracts () throws Error {
            ensure ();

            var data = contractor_dbus.list_all_contracts ();

            return get_contracts_from_data (data);
        }

        /**
         * This searches for available contracts of a particular file type.
         *
         * @param mime_type Mimetype of file.
         * @return List of contracts that support the given mimetype.
         */
        public static Gee.List<Contract> get_contracts_by_mime (string mime_type) throws Error {
            ensure ();

            var data = contractor_dbus.get_contracts_by_mime (mime_type);

            return get_contracts_from_data (data);
        }

        /**
         * Generate contracts for a list of mimetypes.
         *
         * Only the contracts that support all the mimetypes are returned.
         *
         * @param mime_types Array of mimetypes.
         * @return List of contracts that support the given mimetypes.
         */
        public static Gee.List<Contract> get_contracts_by_mimelist (string[] mime_types) throws Error {
            ensure ();

            var data = contractor_dbus.get_contracts_by_mimelist (mime_types);

            return get_contracts_from_data (data);
        }

        private static Gee.List<Contract> get_contracts_from_data (ContractData[] data) {
            var contract_list = new Gee.LinkedList<Contract> ();

            if (data != null) {
                foreach (var contract_data in data) {
                    string contract_id = contract_data.id;

                    // See if we have a contract already. Otherwise create a new one.
                    // We do this in order to be able to compare contracts by reference
                    // from client code.
                    var contract = contracts.get (contract_id);

                    if (contract == null) {
                        contract = new GenericContract (contract_data);
                        contracts.set (contract_id, contract);
                    } else {
                        contract.update_data (contract_data);
                    }

                    contract_list.add (contract);
                }
            }

            return contract_list;
        }
    }
}