// Supabase connection. The anon key is public by design. Row-level security in
// the sweeep schema is what protects the data.
// Project is shared with other applications, so the client is pinned to the
// sweeep schema. That schema must be listed under Settings -> API -> Exposed
// schemas or every request returns an empty result.

// Bundled locally rather than loaded from a CDN. Removes a third-party request
// from the critical path, which was adding seconds to first load. Rebuild with:
//   npx esbuild entry.js --bundle --format=esm --minify --outfile=supabase.js
// where entry.js re-exports createClient from @supabase/supabase-js.
import { createClient } from './supabase.js';

export const SUPABASE_URL = 'https://ciuevdpwokgltibsahyp.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_mZehy_-aKZ1fIRF-Vw1G4Q_nYiHP2px';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  db: { schema: 'sweeep' },
  // Keeps the session in browser storage and refreshes it in the background, so
  // the access key is entered once per browser rather than once per visit.
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    storageKey: 'sweeep-review-session',
  },
});

// Committee roster. These are login identifiers for pre-created accounts. No
// mail is sent to them by this application.
export const REVIEWERS = [
  { name: 'Casey Wichman',  login: 'wichman@gatech.edu' },
  { name: 'Laura Taylor',   login: 'ltaylor75@gatech.edu' },
  { name: 'Dylan Brewer',   login: 'brewer@gatech.edu' },
  { name: 'Matthew Oliver', login: 'matthew.oliver@econ.gatech.edu' },
  { name: 'Gaurav Doshi',   login: 'gdoshi@gatech.edu' },
  { name: 'Bobby Harris',   login: 'bobby.harris@gatech.edu' },
];

export const TRACK_LABEL = { full: 'Full talk', egg: 'Egg-timer' };

export const esc = s => (s ?? '').toString().replace(/[&<>"]/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
