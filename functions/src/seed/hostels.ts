/** Hostel seed - exactly the table in DATABASE_SCHEMA.md. Blocks are never merged (Vasudha E and G are separate). */

export interface HostelSeed {
  hostelId: string;
  displayName: string;
  legacyName: string | null;
  block: string | null;
  category: 'GENERAL' | 'GIRLS';
}

export const HOSTEL_SEED: HostelSeed[] = [
  { hostelId: 'agira', displayName: 'Agira Hall', legacyName: 'Hostel-A', block: null, category: 'GENERAL' },
  { hostelId: 'amritam', displayName: 'Amritam Hall', legacyName: 'Hostel-B', block: null, category: 'GENERAL' },
  { hostelId: 'prithvi', displayName: 'Prithvi Hall', legacyName: 'Hostel-C', block: null, category: 'GENERAL' },
  { hostelId: 'neeram', displayName: 'Neeram Hall', legacyName: 'Hostel-D', block: null, category: 'GENERAL' },
  { hostelId: 'vyan', displayName: 'Vyan Hall', legacyName: 'Hostel-H', block: null, category: 'GENERAL' },
  { hostelId: 'tejas', displayName: 'Tejas Hall', legacyName: 'Hostel-J', block: null, category: 'GENERAL' },
  { hostelId: 'ambaram', displayName: 'Ambaram Hall', legacyName: 'Hostel-K', block: null, category: 'GENERAL' },
  { hostelId: 'viyat', displayName: 'Viyat Hall', legacyName: 'Hostel-L', block: null, category: 'GENERAL' },
  { hostelId: 'anantam', displayName: 'Anantam Hall', legacyName: 'Hostel-M', block: null, category: 'GENERAL' },
  { hostelId: 'vyom', displayName: 'Vyom Hall', legacyName: 'Hostel-O', block: null, category: 'GENERAL' },
  { hostelId: 'frf-g', displayName: 'Hostel-FRF/G', legacyName: null, block: null, category: 'GENERAL' },
  { hostelId: 'vasudha-e', displayName: 'Vasudha Hall - Block E', legacyName: 'Hostel-E', block: 'E', category: 'GIRLS' },
  { hostelId: 'vasudha-g', displayName: 'Vasudha Hall - Block G', legacyName: 'Hostel-G', block: 'G', category: 'GIRLS' },
  { hostelId: 'ira', displayName: 'Ira Hall', legacyName: 'Hostel-I', block: null, category: 'GIRLS' },
  { hostelId: 'ananta', displayName: 'Ananta Hall', legacyName: 'Hostel-N', block: null, category: 'GIRLS' },
  { hostelId: 'dhriti', displayName: 'Dhriti Hall (Hostel-PG)', legacyName: null, block: null, category: 'GIRLS' },
  { hostelId: 'vahni', displayName: 'Vahni Hall', legacyName: 'Hostel-Q', block: null, category: 'GIRLS' },
  { hostelId: 'pavani', displayName: 'Hostel-Pavani Hall', legacyName: 'PG-2', block: null, category: 'GIRLS' },
];
