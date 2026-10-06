export const SITE = {
  name: 'MacPeek',
  tagline: 'The tiny utilities macOS should have built in.',
  altTagline: 'Peek inside your Mac. Without the digging.',
  description:
    'MacPeek is an open-source collection of lightweight native macOS utilities for finding, inspecting and understanding the things macOS makes unnecessarily difficult to see.',
  github: 'https://github.com/mohitkap12-a11y/MACPeek',
  releases: 'https://github.com/mohitkap12-a11y/MACPeek/releases/latest',
  // Flip to true when the first signed release is published. Until then every "Download" button goes to
  // /download/, which says so plainly and shows how to build from source, instead of a GitHub 404.
  hasRelease: false,
};

/** Wording for a utility that is built into the app: honest about there being no download yet. */
export const liveTag = SITE.hasRelease ? 'Available' : 'Ready';
export const liveTagLong = SITE.hasRelease ? 'Available now' : 'Ready · first release pending';
export const liveSentence = SITE.hasRelease ? 'PortPeek is available now.' : 'PortPeek is ready; the first release is on the way.';

/** Where "Download" buttons point. */
export const downloadHref = SITE.hasRelease ? SITE.releases : '/download/';

export const docsNav = [
  { href: '/docs/installation/', label: 'Installation' },
  { href: '/docs/usage/', label: 'Using MacPeek' },
  { href: '/docs/managing-utilities/', label: 'Managing utilities' },
  { href: '/docs/ports/', label: 'PortPeek: ports' },
  { href: '/docs/killing-processes/', label: 'PortPeek: killing safely' },
  { href: '/docs/permissions/', label: 'Permissions' },
  { href: '/docs/troubleshooting/', label: 'Troubleshooting' },
  { href: '/privacy/', label: 'Privacy' },
  { href: '/security/', label: 'Security' },
];

/** Guides (blog). `utility` ties a guide to the Peek that solves the same problem. */
export const blogPosts = [
  { slug: 'how-to-find-what-is-using-a-port-on-mac', label: 'Find what is using a port on Mac', utility: 'portpeek' },
  { slug: 'how-to-kill-a-process-on-a-port-on-mac', label: 'Kill a process on a port on Mac', utility: 'portpeek' },
  { slug: 'how-to-free-port-3000-on-mac', label: 'Free port 3000 on Mac', utility: 'portpeek' },
  { slug: 'lsof-mac-find-process-by-port', label: 'lsof on Mac: find process by port', utility: 'portpeek' },
  { slug: 'mac-port-manager', label: 'Mac port manager', utility: 'portpeek' },
  { slug: 'mac-port-monitor', label: 'Mac port monitor', utility: 'portpeek' },
  { slug: 'how-to-check-monitor-refresh-rate-on-mac', label: 'Check monitor refresh rate on Mac', utility: 'displaypeek' },
  { slug: 'how-to-see-usb-devices-on-mac', label: 'See USB devices on Mac', utility: 'usbpeek' },
  { slug: 'why-wont-my-mac-go-to-sleep', label: "Why won't my Mac go to sleep?", utility: 'sleeppeek' },
  { slug: 'how-to-check-macbook-battery-health', label: 'Check MacBook battery health', utility: 'batterypeek' },
  { slug: 'how-to-check-wifi-signal-strength-on-mac', label: 'Check Wi-Fi signal strength on Mac', utility: 'netpeek' },
];

export const blogNav = blogPosts.map((p) => ({ href: `/blog/${p.slug}/`, label: p.label }));
