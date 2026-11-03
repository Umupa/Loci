import { transport } from "../../../platform/transport";

/** Command-line access to this Loci, as the host reports it. */
export type CliAccess = {
  enabled: boolean;
  identifier: string;
  executable: string | null;
  tokenPath: string | null;
  /** Where Install puts `loci`; null where it cannot (Windows). */
  installPath: string | null;
  installed: boolean;
};

export const loadCliAccess = () => transport.call<CliAccess>("cli_access_status");
export const setCliAccess = (enabled: boolean) => transport.call<CliAccess>("cli_access_set", { enabled });
export const rotateCliToken = () => transport.call<void>("cli_access_rotate");
export const installCli = () => transport.call<CliAccess>("cli_install");
