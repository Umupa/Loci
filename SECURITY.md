# Security policy

## Supported versions

Loci is pre-1.0. Security fixes go into `main` and the latest release; older releases are not patched.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: **[Report a vulnerability](https://github.com/Umupa/Loci/security/advisories/new)**. Do not open a public issue or pull request for a security problem.

Include what you can of:

- the Loci version or commit, and your operating system,
- the agent CLI involved, if any,
- the steps to reproduce, and what an attacker gains.

Loci is maintained in spare time. Expect an acknowledgement within about a week; how long a fix takes depends on the severity. Reports are handled in private until a fix is available, and reporters are credited in the advisory unless they ask not to be.

## What counts

Loci runs agent CLIs with your user's permissions, and it is not a sandbox. The permission mode you choose decides when Loci asks you before the CLI acts. An agent doing something its permission mode allows, including after a prompt injection, is how the mode is meant to work.

These are in scope:

- Using the local control channel without a grant for an active turn or the command-line token, or reaching a namespace or a project the grant does not cover (see [The control channel](docs/architecture.md#the-control-channel)).
- Another user account on the same machine driving Loci through the command line, or the command-line token being readable by one.
- Bypassing a rule Loci enforces itself, such as the learning map rules, canvas ownership, or the loopback-only restrictions.
- Script execution in the app window from agent output, notes, canvases or links, including a Content Security Policy bypass.
- Reading or writing files outside what a feature is meant to reach, through app commands or `loci://` links.
- Link previews reaching a non-public address.
- Leaking a token, such as the Claude Code token used for the usage meter or a control grant, anywhere it is not documented to go.
- Tampering with the bundled MCP servers or with release artifacts.

These are out of scope:

- Bugs in the agent CLIs or the models themselves; report them to their makers.
- Anything that needs the attacker to already run code as you. Such an attacker can read Loci's database directly.
- The warning your OS shows for a release build that is not notarized or signed.
- Vulnerabilities in a dependency with no path to Loci; Dependabot tracks those.

## The `loci` command line

`loci` in a terminal can drive a running Loci: create and change mentors, send them messages, write to their libraries and open things in the reader ([docs/cli.md](docs/cli.md)). This access is **on by default**. It is guarded by a token in Loci's data folder that only your user account can read. Settings → General → Command line turns it off (removing the token) and rotates the token.

Anything that runs as you can read that token, including an agent in Full access mode, just as it can read Loci's database. Turn command-line access off if you do not use it. Each Loci build (the installed app, Loci Dev, a QA build) has its own token, so a token for one does not open another.

## Where to read more

[Data and privacy](README.md#data-and-privacy) says what Loci stores and sends. [Network and trust boundaries](docs/architecture.md#network-and-trust-boundaries) says where the lines are drawn in the code.
