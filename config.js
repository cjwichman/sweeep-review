// Supabase connection. The anon key is public by design. Row-level security in
// the sweeep schema is what protects the data.
// Project is shared with other applications, so the client is pinned to the
// sweeep schema. That schema must be listed under Settings -> API -> Exposed
// schemas or every request returns an empty result.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const SUPABASE_URL = 'https://ciuevdpwokgltibsahyp.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_mZehy_-aKZ1fIRF-Vw1G4Q_nYiHP2px';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  db: { schema: 'sweeep' }
});

export const TRACK_LABEL = { full: 'Full talk', egg: 'Egg-timer' };

export const esc = s => (s ?? '').toString().replace(/[&<>"]/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
