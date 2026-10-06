// Website copy for each utility. KEEP IN SYNC with Sources/MacPeekCore/Registry/UtilityCatalog.swift:
// ids, names and availability are verified against that file by tests/catalog.test.mjs.
// Copy for utilities that have not shipped is written in the future tense and every page says "Coming soon".

export type Row = { lead?: string; title: string; sub?: string; badge?: string; tone?: 'good' | 'warn' | 'info' };
export interface Preview {
  title: string; // header inside the mock
  search?: string;
  rows: Row[];
  expanded?: { index: number; kv: [string, string][]; action?: string };
  footer: [string, string];
}
export interface Utility {
  id: string;
  name: string;
  category: 'everyday' | 'developer';
  status: 'available' | 'coming-soon';
  icon: string; // inner SVG (24x24, stroke)
  question: string;
  tagline: string;
  metaTitle: string;
  metaDescription: string;
  problem: string;
  solution: string;
  features: string[];
  how: string[];
  reads: string[];
  access: string;
  /** True if the utility makes network requests when the user runs a check (so "no network access" would be false). */
  networkChecks?: boolean;
  guides: string[]; // blog slugs
  preview: Preview;
}

export const utilities: Utility[] = [
  {
    id: 'portpeek', name: 'PortPeek', category: 'everyday', status: 'available',
    icon: '<circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
    question: 'What is using port 3000?',
    tagline: "See what's using your ports. Kill it in one click.",
    metaTitle: 'PortPeek: Find and Kill the Process Using a Port on Mac | MacPeek',
    metaDescription: 'PortPeek lists every listening TCP and UDP port on your Mac with the process behind it, and frees a port by safely terminating its owner. Free and open source.',
    problem: '“Port 3000 is already in use.” macOS gives you no screen that says which app owns a port, so you drop to Terminal, remember the right lsof flags, copy a PID and hope it is still the right process when you kill it.',
    solution: 'PortPeek shows every listening port visible to your user with the process, PID and address behind it. Search by port, process or PID, and free a port without Terminal. It asks the process to quit gracefully first and re-checks the target so a reused PID is never killed by mistake.',
    features: [
      'Listening TCP and UDP ports, IPv4 and IPv6, with process, PID, address and state',
      'Instant search by port (partial too), process name, PID or address',
      'Safe kill: re-check → verify the same process → SIGTERM → confirm the port is free',
      'Explicit force kill only after a graceful attempt fails, with a second re-check',
      'Clear permission states: can terminate, permission required, protected',
      'Copy port, PID, process name or address; refreshes live only while its screen is open',
    ],
    how: [
      'Open MacPeek and choose PortPeek.',
      'Search for the port or process, then select a row to inspect it.',
      'Kill Process: PortPeek verifies the target, asks it to quit, and confirms the port was released.',
    ],
    reads: ['Listening sockets and the processes that own them, for your user account (via lsof)'],
    access: 'None to view. You can terminate only processes your user owns.',
    guides: ['how-to-find-what-is-using-a-port-on-mac', 'how-to-free-port-3000-on-mac', 'how-to-kill-a-process-on-a-port-on-mac', 'lsof-mac-find-process-by-port'],
    preview: {
      title: 'PortPeek', search: 'Search ports, processes or PIDs…',
      rows: [
        { lead: '3000', title: 'node', sub: 'PID 18432', badge: 'TCP' },
        { lead: '5173', title: 'node', sub: 'PID 19283', badge: 'TCP' },
        { lead: '5432', title: 'postgres', sub: 'PID 921', badge: 'TCP' },
        { lead: '6379', title: 'redis-server', sub: 'PID 1042', badge: 'TCP' },
      ],
      expanded: { index: 0, kv: [['Address', '127.0.0.1:3000'], ['State', 'LISTEN'], ['Status', '✓ Can terminate']], action: 'Kill Process' },
      footer: ['4 listening ports', 'Updated just now'],
    },
  },
  {
    id: 'displaypeek', name: 'DisplayPeek', category: 'everyday', status: 'available',
    icon: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    question: 'What display configuration am I actually running?',
    tagline: 'Know exactly how your displays are configured.',
    metaTitle: 'DisplayPeek: See Your Real Monitor Resolution and Refresh Rate | MacPeek',
    metaDescription: "DisplayPeek shows each display's panel resolution, desktop resolution, refresh rate and scaling on your Mac, and copies the details in one click. Free and open source.",
    problem: 'Your external monitor looks soft, or you paid for 120 Hz. System Settings shows a slider and a list of scaled modes, but not a plain answer to “what is this display really running at?”.',
    solution: 'DisplayPeek lists every connected display with its panel resolution, the “looks like” desktop resolution, the refresh rate and the scaling that results, plus anything else macOS reports about it. One click copies it all. Where macOS does not report a detail (such as cable type), DisplayPeek leaves it out instead of guessing.',
    features: [
      'Name, GPU, main display, mirroring and online state for every display',
      'Panel resolution and the “looks like” desktop resolution, with the refresh rate macOS reports',
      'Scaling worked out from the two: native, HiDPI (2×) or scaled',
      'Everything else macOS reports about the display, shown as reported; serial numbers are always left out',
      'Copy Display Details for support threads and bug reports',
      'Never invents cable, HDR or protocol details that macOS does not report',
    ],
    how: ['Open DisplayPeek from the launcher.', 'Each connected display gets a card with its configuration.', 'Copy the details to share.'],
    reads: ['Display properties from macOS (via system_profiler), only while DisplayPeek is open'],
    access: 'None.',
    guides: ['how-to-check-monitor-refresh-rate-on-mac'],
    preview: {
      title: 'DisplayPeek',
      rows: [
        { title: 'LG HDR WQHD', sub: 'Apple M2 · Main display', badge: '100 Hz', tone: 'info' },
      ],
      expanded: { index: 0, kv: [['Panel resolution', '3440 × 1440'], ['Looks like', '3440 × 1440'], ['Refresh rate', '100 Hz'], ['Scaling', 'Native (1×)']], action: 'Copy Display Details' },
      footer: ['1 display', 'Reads when you open it'],
    },
  },
  {
    id: 'usbpeek', name: 'USBPeek', category: 'everyday', status: 'available',
    icon: '<rect x="7" y="3" width="10" height="7" rx="1.5"/><path d="M10 6h.01M14 6h.01M9 10v3a3 3 0 0 0 6 0v-3M12 16v5"/>',
    question: 'What is connected, and at what speed?',
    tagline: "See what's connected to your Mac.",
    metaTitle: 'USBPeek: See USB and Thunderbolt Devices and Their Speed | MacPeek',
    metaDescription: 'USBPeek lists connected USB devices as a tree with vendor and link speed, and shows your Thunderbolt and USB4 ports. Serial numbers are never read. Free and open source.',
    problem: 'Your external SSD feels slow. Is it on a fast port? Is the cable limiting it? The answer is buried in System Information, in a tree that is hard to read.',
    solution: 'USBPeek shows connected USB devices as a readable tree by bus, with the vendor and the link speed macOS reports for each one, and the status and speed of your Thunderbolt and USB4 ports. Serial numbers are never read, so they cannot be shown or copied by accident.',
    features: [
      'USB devices as a tree by bus, with hubs and the devices behind them',
      'Device name, vendor, and vendor:product ID',
      'The link speed macOS negotiated (for example 480 Mb/s or 5 Gb/s), the USB version the device declares, and its class',
      'Thunderbolt and USB4 ports with their status and speed, and the devices macOS lists on them',
      'Serial numbers are never read: they cannot be displayed, copied or logged',
      'Copy device details',
    ],
    how: ['Open USBPeek from the launcher.', 'Browse the device tree and tap a device for its details.', 'Check the link speed next to each device.'],
    reads: ['USB devices from the I/O registry (ioreg) and Thunderbolt port status (system_profiler), only while USBPeek is open'],
    access: 'None.',
    guides: ['how-to-see-usb-devices-on-mac'],
    preview: {
      title: 'USBPeek',
      rows: [
        { title: 'USB3.1 Hub', sub: 'GenesysLogic', badge: '5 Gb/s', tone: 'info' },
        { title: 'USB2.1 Hub', sub: 'GenesysLogic', badge: '480 Mb/s', tone: 'info' },
        { title: 'USB OPTICAL MOUSE', sub: 'Behind USB2.1 Hub', badge: '1.5 Mb/s' },
      ],
      footer: ['3 USB devices', 'Reads when you open it'],
    },
  },
  {
    id: 'netpeek', name: 'NetPeek', category: 'everyday', status: 'coming-soon',
    icon: '<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>',
    question: 'Is my network connection actually healthy?',
    tagline: 'Understand your network connection.',
    metaTitle: 'NetPeek: Check Your Mac Network, Wi-Fi Signal and Latency | MacPeek',
    metaDescription: 'NetPeek, coming to MacPeek, shows your active interface, IP, gateway, DNS, latency and Wi-Fi signal details where macOS allows, with no aggressive background tests.',
    problem: 'The internet feels flaky. Is it Wi-Fi signal, the router, DNS or your ISP? Answering that today means several Terminal commands and a Wi-Fi menu you have to Option-click.',
    solution: 'NetPeek will show your active interface, addresses, gateway and DNS, plus reachability and latency and the Wi-Fi details macOS exposes. Checks run only when you ask: no continuous speed tests.',
    features: [
      'Interface, local IPv4/IPv6, gateway and DNS at a glance',
      'Reachability and latency measured on request',
      'Wi-Fi signal strength, channel, band and link rate where APIs permit',
      'No continuous or hidden speed tests; throughput tests are user-initiated',
      'Copy diagnostics',
    ],
    how: ['Open NetPeek from the launcher.', 'Read your interface and gateway details.', 'Run a check to measure latency.'],
    reads: ['Network interface configuration; latency to your gateway and DNS only when you run a check'],
    access: 'Wi-Fi network name may require Location access on recent macOS versions.',
    networkChecks: true,
    guides: ['how-to-check-wifi-signal-strength-on-mac'],
    preview: {
      title: 'NetPeek',
      rows: [
        { lead: 'Wi-Fi', title: 'en0', sub: '192.168.1.24', badge: 'Connected', tone: 'good' },
        { lead: 'Gateway', title: '192.168.1.1', sub: 'Latency 4 ms', badge: 'OK', tone: 'good' },
        { lead: 'DNS', title: '1.1.1.1', sub: 'Lookup 12 ms' },
        { lead: 'Signal', title: '−52 dBm', sub: 'Channel 36 · 5 GHz', badge: 'Good', tone: 'good' },
      ],
      footer: ['Checks run on request', 'Preview'],
    },
  },
  {
    id: 'batterypeek', name: 'BatteryPeek', category: 'everyday', status: 'coming-soon',
    icon: '<rect x="2" y="8" width="17" height="9" rx="2"/><path d="M22 11v3M6 11v3M10 11v3"/>',
    question: 'What is my MacBook battery actually doing?',
    tagline: 'Understand your MacBook battery.',
    metaTitle: 'BatteryPeek: MacBook Battery Health, Cycles and Charging | MacPeek',
    metaDescription: 'BatteryPeek, coming to MacPeek, shows charge, power source, cycle count and the health indicators macOS reports, without claiming precision the OS does not give.',
    problem: 'How healthy is your battery, how many cycles has it done, and why is it not charging? macOS spreads the answers over Settings, System Information and Terminal.',
    solution: 'BatteryPeek will show charge, power source, charging state, cycle count and the health and capacity indicators macOS reports. Estimates are labelled as estimates.',
    features: [
      'Charge percentage, power source and charging state',
      'Cycle count and capacity/health indicators as macOS reports them',
      'Charging details and time estimates where available',
      'Temperature only where macOS exposes it reliably',
      'Never claims exact degradation when the OS gives an estimate',
    ],
    how: ['Open BatteryPeek from the launcher.', 'Read the live state and health indicators.', 'Copy details if you need to share them.'],
    reads: ['Battery and power-source information from macOS power services'],
    access: 'None.',
    guides: ['how-to-check-macbook-battery-health'],
    preview: {
      title: 'BatteryPeek',
      rows: [
        { lead: '92%', title: 'On battery', sub: 'Not charging', badge: '7:42 left' },
        { lead: '214', title: 'Cycle count', sub: 'Reported by macOS' },
        { lead: '91%', title: 'Maximum capacity', sub: 'Estimate from macOS', badge: 'Estimate', tone: 'info' },
      ],
      footer: ['MacBook battery', 'Preview'],
    },
  },
  {
    id: 'sleeppeek', name: 'SleepPeek', category: 'everyday', status: 'available',
    icon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
    question: "Why isn't my Mac sleeping?",
    tagline: "Find out why your Mac isn't sleeping.",
    metaTitle: "SleepPeek: Find Out Why Your Mac Won't Sleep or Keeps Waking | MacPeek",
    metaDescription: "SleepPeek is a read-only view of what keeps your Mac awake: sleep assertions and the processes behind them, plus recent wake reasons, with facts kept apart from guesses.",
    problem: 'Your Mac will not go to sleep, or wakes in the night. Something is holding it awake, but which process, and why, is hidden in pmset output.',
    solution: 'SleepPeek lists the active sleep assertions and the processes holding them, and can load recent sleep and wake events with the reason macOS logged. Every statement is labelled: “Reported by macOS” for what the system says, “Likely (inference)” for a common explanation. It is read-only and never changes a power setting.',
    features: [
      'A clear headline: what is keeping the Mac or its display awake, if anything',
      'Each blocking assertion with its process, PID, type, name and how long it has been held',
      'macOS’s own “sleep prevented by” summary, quoted as reported',
      'Facts and inferences labelled separately, with only a short list of conservative explanations',
      'Recent sleep, wake and background-wake events with the reason exactly as macOS logged it, loaded only when you ask (it can take up to a minute)',
      'Read-only: it never changes power settings. Copy the diagnosis for a bug report.',
    ],
    how: ['Open SleepPeek from the launcher.', 'See what is currently blocking sleep and what macOS says about it.', 'Load the recent sleep and wake history when you want it.'],
    reads: ['Power-management assertions and settings (pmset); the sleep/wake log only when you ask for it'],
    access: 'None.',
    guides: ['why-wont-my-mac-go-to-sleep'],
    preview: {
      title: 'SleepPeek',
      rows: [
        { lead: 'Status', title: 'Something is keeping your Mac awake', badge: 'Verified', tone: 'warn' },
        { lead: 'Holder', title: 'bluetoothd · PID 4647', sub: 'PreventUserIdleSystemSleep', badge: 'Verified', tone: 'good' },
        { lead: 'Holder', title: 'powerd · PID 4598', sub: 'Normal while the display is on', badge: 'Inference', tone: 'info' },
      ],
      footer: ['Read-only', 'Never changes power settings'],
    },
  },
  {
    id: 'filelockpeek', name: 'FileLockPeek', category: 'developer', status: 'available',
    icon: '<path d="M6 3h8l4 4v14H6z"/><rect x="9" y="12" width="6" height="5" rx="1"/><path d="M10 12v-1.5a2 2 0 0 1 4 0V12"/>',
    question: 'What process is using this file?',
    tagline: "Find what's holding a file open.",
    metaTitle: 'FileLockPeek: See Which Process Is Using a File on Mac | MacPeek',
    metaDescription: 'FileLockPeek shows which of your processes have a file or folder open, locked or as their working directory, and can safely end one. Free and open source.',
    problem: '“The operation can’t be completed because the item is in use.” Or a drive that will not eject. Something has the file or folder open, but macOS does not tell you what.',
    solution: 'FileLockPeek lets you choose a file or folder (or drop it in, or paste a path) and lists the processes holding it, with the process, PID and how it holds the path: open for reading or writing, locked, working directory, executable or memory-mapped. Ending a holder is optional and uses the same safe-termination checks as PortPeek; MacPeek never terminates anything by default.',
    features: [
      'Choose, drop or paste a file or folder; folder scans include everything inside',
      'Each holder shown with process name, PID and user',
      'How it holds the path: open (read/write), locked, working directory, executable or memory-mapped',
      'Copy PID or path, and reveal the item in Finder',
      'Optional Kill Process through the shared safe-termination service: re-checked, SIGTERM first, explicit force kill',
      'Scans only when you ask: no polling, nothing running in the background',
    ],
    how: [
      'Open FileLockPeek and choose, drop or paste a path.',
      'See which processes hold it and how.',
      'Optionally end a holder you own: MacPeek re-checks it, asks it to quit, and confirms the file was released.',
    ],
    reads: ['Open files of processes owned by your user (via lsof), only for the path you choose, only when you scan'],
    access: 'None to scan. Other users’ processes are not listed, and you can terminate only processes your user owns.',
    guides: ['how-to-find-what-process-is-using-a-file-on-mac'],
    preview: {
      title: 'FileLockPeek', search: '~/Projects/app/data.db',
      rows: [
        { title: 'Docker Desktop', sub: 'PID 18432', badge: 'Open · read/write', tone: 'warn' },
        { title: 'sqlite3', sub: 'PID 20311', badge: 'Open · read' },
        { title: 'zsh', sub: 'PID 5120', badge: 'Working dir' },
      ],
      expanded: { index: 0, kv: [['User', 'you'], ['Holds', 'data.db (3u)'], ['Status', '✓ Can terminate']], action: 'Kill Process' },
      footer: ['3 processes', 'Scans only when you ask'],
    },
  },
  {
    id: 'processpeek', name: 'ProcessPeek', category: 'developer', status: 'available',
    icon: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="10" y="10" width="4" height="4"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
    question: 'What exactly is this process?',
    tagline: 'Inspect a process and its relationships.',
    metaTitle: 'ProcessPeek: Inspect a Mac Process, Its Parent, Ports and Children | MacPeek',
    metaDescription: "ProcessPeek shows a Mac process's path, parent, user, start time, command line, listening ports and children. It is deliberately not an Activity Monitor replacement.",
    problem: 'You see an unfamiliar process name. Where did it come from, what started it, and what is it listening on?',
    solution: 'ProcessPeek lists your processes in a searchable list. Open one to see its executable path, parent, user, start time, how long it has been running, CPU and memory, its full command line, the ports it listens on, and its child processes, and jump to the parent or any child. It is deliberately not Activity Monitor: it explains one process rather than charting all of them.',
    features: [
      'Search by name, PID, user or path; sort by name, CPU, memory or PID',
      'Name, PID, parent, user, start time and running time',
      'Executable path and the full command line, read only when you open a process',
      'Listening TCP and UDP ports of that process',
      'Parent and children, one click to jump to any of them',
      'Your processes by default; other users’ processes only if you include them',
      'Read-only: it never ends or changes a process',
    ],
    how: ['Open ProcessPeek and search for a process.', 'Open a row to read its identity and relationships.', 'Jump to its parent or children.'],
    reads: ['The process list (ps); a process’s command line and listening ports only when you open it'],
    access: 'None. Some details are unavailable for other users’ processes.',
    guides: [],
    preview: {
      title: 'ProcessPeek', search: 'Search processes…',
      rows: [
        { title: 'node', sub: 'PID 18432 · you', badge: '24 MB', tone: 'info' },
        { title: 'esbuild', sub: 'PID 18440 · you', badge: '31 MB' },
        { title: 'zsh', sub: 'PID 5120 · you', badge: '3 MB' },
      ],
      expanded: { index: 0, kv: [['Parent', 'npm (PID 18420)'], ['Running for', '2h 14m'], ['Listening ports', 'TCP *:3000'], ['Children', '1 process']], action: 'Copy command line' },
      footer: ['Read-only', 'Reads when you open it'],
    },
  },
  {
    id: 'diskpeek', name: 'DiskPeek', category: 'developer', status: 'available',
    icon: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 14h.01M11 14h6"/>',
    question: 'Which app is using my disk right now?',
    tagline: 'See which processes are hitting your disk.',
    metaTitle: 'DiskPeek: See Which App Is Using Your Mac Disk Right Now | MacPeek',
    metaDescription: 'DiskPeek samples per-process disk reads and writes only while it is open and labels every value as sampled, so you can find what is hammering your disk.',
    problem: 'The fans spin up and the disk light is on. Which app is reading and writing so much?',
    solution: 'DiskPeek samples the disk read and write counters macOS keeps for each of your processes, every couple of seconds, and shows the busiest ones as rates and as totals since you opened it. Everything is labelled as sampled. Sampling stops the moment you leave the screen, and it starts from a fresh baseline each time.',
    features: [
      'Per-process read and write rates over the last sampling interval',
      'Totals since you opened DiskPeek, so brief bursts are not missed',
      'Order by what is busy right now or by the total since opening',
      'Clearly labelled as sampled values',
      'Samples only while the screen is open; nothing runs in the background',
      'Other users’ and protected processes are counted but not shown, and it says so',
      'Not a disk-space cleaner',
    ],
    how: ['Open DiskPeek from the launcher.', 'Wait one sampling interval for the first rates.', 'Leave the screen and sampling stops.'],
    reads: ['Per-process disk I/O counters (libproc) for processes your user can inspect, only while DiskPeek is open'],
    access: 'None. Other users’ processes are not shown.',
    guides: [],
    preview: {
      title: 'DiskPeek',
      rows: [
        { title: 'Docker', sub: 'PID 612 · 4.2 GB read, 1.1 GB written since opened', badge: 'Sampled', tone: 'info' },
        { title: 'Photos', sub: 'PID 1840 · 380 MB read, 12 MB written since opened', badge: 'Sampled', tone: 'info' },
        { title: 'Chrome', sub: 'PID 920 · 40 MB read, 18 MB written since opened', badge: 'Sampled', tone: 'info' },
      ],
      footer: ['Sampled while open', 'Stops when you leave'],
    },
  },
  {
    id: 'envpeek', name: 'EnvPeek', category: 'developer', status: 'available',
    icon: '<path d="M4 17l6-5-6-5M12 19h8"/>',
    question: 'What environment variables does this environment see?',
    tagline: 'Inspect and search environment variables.',
    metaTitle: 'EnvPeek: Search and Inspect Environment Variables and PATH on Mac | MacPeek',
    metaDescription: 'EnvPeek lets you search environment variables, inspect PATH entry by entry and copy NAME=value, labelling where each value comes from so nothing looks global by mistake.',
    problem: 'Why is the wrong Node first in PATH? Does this app even see that variable? The answer depends on which shell or process you ask.',
    solution: 'EnvPeek lets you search variables, inspect PATH entry by entry, and copy a name, a value or NAME=value. It shows MacPeek’s own environment, which is usually not your terminal’s, or the environment of one running process whose PID you enter. Each list is labelled by its source, so a per-process value is never presented as global.',
    features: [
      'Search names and values; copy the name, the value or NAME=value',
      'PATH, MANPATH and similar variables entry by entry, flagging duplicates, missing folders, relative and empty entries',
      'Two sources, always labelled: MacPeek’s own environment, or one process you choose by PID',
      'Values that look like credentials (tokens, secrets, passwords, keys) are hidden until you reveal them',
      'Values stay on screen and in memory only while the screen is open; they are never logged or stored',
      'Honest about limits: macOS hides the environment of protected system processes and of other users’ processes',
    ],
    how: ['Open EnvPeek from the launcher.', 'Search for a variable, or switch to a process and enter its PID.', 'Copy it, or open PATH entry by entry.'],
    reads: ['MacPeek’s own environment and, where macOS permits, the environment of one process whose PID you enter'],
    access: 'None. Values are shown on screen only and never logged.',
    guides: [],
    preview: {
      title: 'EnvPeek', search: 'PATH',
      rows: [
        { lead: 'PATH', title: '/opt/homebrew/bin:/usr/bin…', sub: '8 entries · 1 duplicate', badge: 'This app' },
        { lead: 'SHELL', title: '/bin/zsh', badge: 'This app' },
        { lead: 'LANG', title: 'en_US.UTF-8', badge: 'This app' },
      ],
      footer: ['Values never logged', 'Source always labelled'],
    },
  },
  {
    id: 'dnspeek', name: 'DNSPeek', category: 'developer', status: 'coming-soon',
    icon: '<rect x="3" y="4" width="18" height="6" rx="1.5"/><rect x="3" y="14" width="18" height="6" rx="1.5"/><path d="M7 7h.01M7 17h.01"/>',
    question: 'Which DNS servers is my Mac using, and do they respond?',
    tagline: 'Inspect DNS configuration and resolver behavior.',
    metaTitle: 'DNSPeek: See Which DNS Servers Your Mac Uses and How Fast | MacPeek',
    metaDescription: 'DNSPeek, coming to MacPeek, is a read-only view of your active interface, resolver configuration and DNS servers, with lookup latency measured on request.',
    problem: 'Pages hang or a domain will not resolve. Which DNS servers is your Mac actually asking, and are they answering?',
    solution: 'DNSPeek will show the active interface, resolver configuration and DNS servers, and measure lookup latency when you ask. It is read-only and never changes DNS settings.',
    features: [
      'Active interface and DNS servers',
      'Resolver configuration and search domains',
      'Lookup latency measured on request',
      'Read-only: never changes DNS settings',
    ],
    how: ['Open DNSPeek from the launcher.', 'Read your resolver configuration.', 'Run a lookup to measure latency.'],
    reads: ['System resolver configuration; lookups only when you run a check'],
    access: 'None.',
    networkChecks: true,
    guides: [],
    preview: {
      title: 'DNSPeek',
      rows: [
        { lead: 'Interface', title: 'Wi-Fi (en0)', badge: 'Active', tone: 'good' },
        { lead: 'DNS', title: '1.1.1.1', sub: '1.0.0.1' },
        { lead: 'Lookup', title: 'apple.com', sub: '14 ms', badge: 'OK', tone: 'good' },
      ],
      footer: ['Read-only', 'Preview'],
    },
  },
];

export const byId = (id: string) => utilities.find((u) => u.id === id);
export const available = utilities.filter((u) => u.status === 'available');
export const comingSoon = utilities.filter((u) => u.status === 'coming-soon');
