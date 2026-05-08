/**
 * Comprehensive device model seed data.
 * Called once during migration / initial setup.
 */

export interface ManufacturerSeed {
  name: string;
  slug: string;
}

export interface DeviceModelSeed {
  manufacturer_slug: string;
  name: string;
  slug: string;
  category: 'phone' | 'tablet' | 'laptop' | 'desktop' | 'console' | 'tv' | 'other';
  release_year: number;
  is_popular: boolean;
}

export const MANUFACTURERS: ManufacturerSeed[] = [
  { name: 'Apple',     slug: 'apple' },
  { name: 'Samsung',   slug: 'samsung' },
  { name: 'Google',    slug: 'google' },
  { name: 'Motorola',  slug: 'motorola' },
  { name: 'LG',        slug: 'lg' },
  { name: 'OnePlus',   slug: 'oneplus' },
  { name: 'Sony',      slug: 'sony' },
  { name: 'Nokia',     slug: 'nokia' },
  { name: 'HTC',       slug: 'htc' },
  { name: 'Huawei',    slug: 'huawei' },
  { name: 'Microsoft', slug: 'microsoft' },
  { name: 'Dell',      slug: 'dell' },
  { name: 'HP',        slug: 'hp' },
  { name: 'Lenovo',    slug: 'lenovo' },
  { name: 'Asus',      slug: 'asus' },
  { name: 'Acer',      slug: 'acer' },
  { name: 'Nintendo',  slug: 'nintendo' },
  { name: 'Sony PlayStation', slug: 'playstation' },
  { name: 'Xbox',      slug: 'xbox' },
  { name: 'Steam',     slug: 'steam' },
  { name: 'TCL',       slug: 'tcl' },
  { name: 'Vizio',     slug: 'vizio' },
  { name: 'Hisense',   slug: 'hisense' },
  { name: 'Philips',   slug: 'philips' },
  { name: 'Alcatel',   slug: 'alcatel' },
  { name: 'ZTE',       slug: 'zte' },
  { name: 'Xiaomi',    slug: 'xiaomi' },
  { name: 'realme',    slug: 'realme' },
  { name: 'Other',     slug: 'other' },
];

export const DEVICE_MODELS: DeviceModelSeed[] = [
  // ─── Apple iPhone ───────────────────────────────────────────────────────────
  { manufacturer_slug: 'apple', name: 'iPhone 16 Pro Max',  slug: 'iphone-16-pro-max',  category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 16 Pro',      slug: 'iphone-16-pro',      category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 16 Plus',     slug: 'iphone-16-plus',     category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 16',          slug: 'iphone-16',          category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 15 Pro Max',  slug: 'iphone-15-pro-max',  category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 15 Pro',      slug: 'iphone-15-pro',      category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 15 Plus',     slug: 'iphone-15-plus',     category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 15',          slug: 'iphone-15',          category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 14 Pro Max',  slug: 'iphone-14-pro-max',  category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 14 Pro',      slug: 'iphone-14-pro',      category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 14 Plus',     slug: 'iphone-14-plus',     category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 14',          slug: 'iphone-14',          category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 13 Pro Max',  slug: 'iphone-13-pro-max',  category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 13 Pro',      slug: 'iphone-13-pro',      category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 13 mini',     slug: 'iphone-13-mini',     category: 'phone', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 13',          slug: 'iphone-13',          category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 12 Pro Max',  slug: 'iphone-12-pro-max',  category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 12 Pro',      slug: 'iphone-12-pro',      category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 12 mini',     slug: 'iphone-12-mini',     category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 12',          slug: 'iphone-12',          category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 11 Pro Max',  slug: 'iphone-11-pro-max',  category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 11 Pro',      slug: 'iphone-11-pro',      category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 11',          slug: 'iphone-11',          category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone XS Max',      slug: 'iphone-xs-max',      category: 'phone', release_year: 2018, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone XS',          slug: 'iphone-xs',          category: 'phone', release_year: 2018, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone XR',          slug: 'iphone-xr',          category: 'phone', release_year: 2018, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone X',           slug: 'iphone-x',           category: 'phone', release_year: 2017, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 8 Plus',      slug: 'iphone-8-plus',      category: 'phone', release_year: 2017, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 8',           slug: 'iphone-8',           category: 'phone', release_year: 2017, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 7 Plus',      slug: 'iphone-7-plus',      category: 'phone', release_year: 2016, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 7',           slug: 'iphone-7',           category: 'phone', release_year: 2016, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone SE (3rd Gen)', slug: 'iphone-se-3rd',     category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone SE (2nd Gen)', slug: 'iphone-se-2nd',     category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone SE (1st Gen)', slug: 'iphone-se-1st',     category: 'phone', release_year: 2016, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 6s Plus',     slug: 'iphone-6s-plus',     category: 'phone', release_year: 2015, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 6s',          slug: 'iphone-6s',          category: 'phone', release_year: 2015, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 6 Plus',      slug: 'iphone-6-plus',      category: 'phone', release_year: 2014, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 6',           slug: 'iphone-6',           category: 'phone', release_year: 2014, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 5s',          slug: 'iphone-5s',          category: 'phone', release_year: 2013, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 5c',          slug: 'iphone-5c',          category: 'phone', release_year: 2013, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPhone 5',           slug: 'iphone-5',           category: 'phone', release_year: 2012, is_popular: false },

  // ─── Apple iPad ─────────────────────────────────────────────────────────────
  { manufacturer_slug: 'apple', name: 'iPad Pro 12.9" (6th Gen)', slug: 'ipad-pro-12-9-6th', category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Pro 11" (4th Gen)',   slug: 'ipad-pro-11-4th',   category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Pro 12.9" (5th Gen)', slug: 'ipad-pro-12-9-5th', category: 'tablet', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Pro 11" (3rd Gen)',   slug: 'ipad-pro-11-3rd',   category: 'tablet', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Pro 12.9" (4th Gen)', slug: 'ipad-pro-12-9-4th', category: 'tablet', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Pro 11" (2nd Gen)',   slug: 'ipad-pro-11-2nd',   category: 'tablet', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Air (5th Gen)',       slug: 'ipad-air-5th',       category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Air (4th Gen)',       slug: 'ipad-air-4th',       category: 'tablet', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Air (3rd Gen)',       slug: 'ipad-air-3rd',       category: 'tablet', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad mini (6th Gen)',      slug: 'ipad-mini-6th',      category: 'tablet', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad mini (5th Gen)',      slug: 'ipad-mini-5th',      category: 'tablet', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad mini 4',              slug: 'ipad-mini-4',        category: 'tablet', release_year: 2015, is_popular: false },
  { manufacturer_slug: 'apple', name: 'iPad (10th Gen)',          slug: 'ipad-10th',          category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad (9th Gen)',           slug: 'ipad-9th',           category: 'tablet', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad (8th Gen)',           slug: 'ipad-8th',           category: 'tablet', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad (7th Gen)',           slug: 'ipad-7th',           category: 'tablet', release_year: 2019, is_popular: false },

  // ─── Apple MacBook / Mac ────────────────────────────────────────────────────
  { manufacturer_slug: 'apple', name: 'MacBook Pro 16" (M3)',   slug: 'macbook-pro-16-m3',   category: 'laptop', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 14" (M3)',   slug: 'macbook-pro-14-m3',   category: 'laptop', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 16" (M2)',   slug: 'macbook-pro-16-m2',   category: 'laptop', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 14" (M2)',   slug: 'macbook-pro-14-m2',   category: 'laptop', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 15" (M2)',   slug: 'macbook-air-15-m2',   category: 'laptop', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 13" (M2)',   slug: 'macbook-air-13-m2',   category: 'laptop', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 13" (M1)',   slug: 'macbook-air-13-m1',   category: 'laptop', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 13" (M1)',   slug: 'macbook-pro-13-m1',   category: 'laptop', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 16" (Intel)', slug: 'macbook-pro-16-intel', category: 'laptop', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 15" (Intel)', slug: 'macbook-pro-15-intel', category: 'laptop', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 13" (Intel)', slug: 'macbook-pro-13-intel', category: 'laptop', release_year: 2020, is_popular: false },

  // ─── Samsung Galaxy S series ─────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy S24 Ultra',  slug: 'galaxy-s24-ultra',  category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S24+',       slug: 'galaxy-s24-plus',   category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S24',        slug: 'galaxy-s24',        category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S23 Ultra',  slug: 'galaxy-s23-ultra',  category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S23+',       slug: 'galaxy-s23-plus',   category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S23',        slug: 'galaxy-s23',        category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S22 Ultra',  slug: 'galaxy-s22-ultra',  category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S22+',       slug: 'galaxy-s22-plus',   category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S22',        slug: 'galaxy-s22',        category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S21 Ultra',  slug: 'galaxy-s21-ultra',  category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S21+',       slug: 'galaxy-s21-plus',   category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S21',        slug: 'galaxy-s21',        category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S21 FE',     slug: 'galaxy-s21-fe',     category: 'phone', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S20 Ultra',  slug: 'galaxy-s20-ultra',  category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S20+',       slug: 'galaxy-s20-plus',   category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S20',        slug: 'galaxy-s20',        category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S20 FE',     slug: 'galaxy-s20-fe',     category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S10+',       slug: 'galaxy-s10-plus',   category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S10',        slug: 'galaxy-s10',        category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S10e',       slug: 'galaxy-s10e',       category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S10 5G',     slug: 'galaxy-s10-5g',     category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S9+',        slug: 'galaxy-s9-plus',    category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S9',         slug: 'galaxy-s9',         category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S8+',        slug: 'galaxy-s8-plus',    category: 'phone', release_year: 2017, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S8',         slug: 'galaxy-s8',         category: 'phone', release_year: 2017, is_popular: false },

  // ─── Samsung Galaxy Note ─────────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy Note 20 Ultra', slug: 'galaxy-note-20-ultra', category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Note 20',       slug: 'galaxy-note-20',       category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Note 10+',      slug: 'galaxy-note-10-plus',  category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Note 10',       slug: 'galaxy-note-10',       category: 'phone', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Note 9',        slug: 'galaxy-note-9',        category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy Note 8',        slug: 'galaxy-note-8',        category: 'phone', release_year: 2017, is_popular: false },

  // ─── Samsung Galaxy Z ─────────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Fold 5',   slug: 'galaxy-z-fold-5',   category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Flip 5',   slug: 'galaxy-z-flip-5',   category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Fold 4',   slug: 'galaxy-z-fold-4',   category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Flip 4',   slug: 'galaxy-z-flip-4',   category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Fold 3',   slug: 'galaxy-z-fold-3',   category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Flip 3',   slug: 'galaxy-z-flip-3',   category: 'phone', release_year: 2021, is_popular: true  },

  // ─── Samsung Galaxy A series ────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy A55',  slug: 'galaxy-a55',  category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A54',  slug: 'galaxy-a54',  category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A53',  slug: 'galaxy-a53',  category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A52',  slug: 'galaxy-a52',  category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A51',  slug: 'galaxy-a51',  category: 'phone', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A50',  slug: 'galaxy-a50',  category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A35',  slug: 'galaxy-a35',  category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A34',  slug: 'galaxy-a34',  category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A33',  slug: 'galaxy-a33',  category: 'phone', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A32',  slug: 'galaxy-a32',  category: 'phone', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A25',  slug: 'galaxy-a25',  category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A24',  slug: 'galaxy-a24',  category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A23',  slug: 'galaxy-a23',  category: 'phone', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A15',  slug: 'galaxy-a15',  category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A14',  slug: 'galaxy-a14',  category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A13',  slug: 'galaxy-a13',  category: 'phone', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A12',  slug: 'galaxy-a12',  category: 'phone', release_year: 2020, is_popular: false },

  // ─── Samsung Tablets ────────────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S9 Ultra', slug: 'galaxy-tab-s9-ultra', category: 'tablet', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S9+',      slug: 'galaxy-tab-s9-plus',  category: 'tablet', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S9',       slug: 'galaxy-tab-s9',       category: 'tablet', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S8 Ultra', slug: 'galaxy-tab-s8-ultra', category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S8+',      slug: 'galaxy-tab-s8-plus',  category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S8',       slug: 'galaxy-tab-s8',       category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S7+',      slug: 'galaxy-tab-s7-plus',  category: 'tablet', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S7',       slug: 'galaxy-tab-s7',       category: 'tablet', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab A8',       slug: 'galaxy-tab-a8',       category: 'tablet', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab A7',       slug: 'galaxy-tab-a7',       category: 'tablet', release_year: 2020, is_popular: false },

  // ─── Google Pixel ───────────────────────────────────────────────────────────
  { manufacturer_slug: 'google', name: 'Pixel 9 Pro XL', slug: 'pixel-9-pro-xl', category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 9 Pro',    slug: 'pixel-9-pro',    category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 9',        slug: 'pixel-9',        category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 8 Pro',    slug: 'pixel-8-pro',    category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 8',        slug: 'pixel-8',        category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 8a',       slug: 'pixel-8a',       category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 7 Pro',    slug: 'pixel-7-pro',    category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 7',        slug: 'pixel-7',        category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 7a',       slug: 'pixel-7a',       category: 'phone', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 6 Pro',    slug: 'pixel-6-pro',    category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 6',        slug: 'pixel-6',        category: 'phone', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 6a',       slug: 'pixel-6a',       category: 'phone', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 5',        slug: 'pixel-5',        category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 5a',       slug: 'pixel-5a',       category: 'phone', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 4 XL',     slug: 'pixel-4-xl',     category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 4',        slug: 'pixel-4',        category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 4a',       slug: 'pixel-4a',       category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 4a 5G',    slug: 'pixel-4a-5g',    category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 3 XL',     slug: 'pixel-3-xl',     category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 3',        slug: 'pixel-3',        category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 3a XL',    slug: 'pixel-3a-xl',    category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 3a',       slug: 'pixel-3a',       category: 'phone', release_year: 2019, is_popular: false },

  // ─── Motorola ───────────────────────────────────────────────────────────────
  { manufacturer_slug: 'motorola', name: 'Moto G Power (2024)',  slug: 'moto-g-power-2024',  category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'motorola', name: 'Moto G Stylus (2024)', slug: 'moto-g-stylus-2024', category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto G Power (2023)',  slug: 'moto-g-power-2023',  category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto G Stylus (2023)', slug: 'moto-g-stylus-2023', category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto G Power (2022)',  slug: 'moto-g-power-2022',  category: 'phone', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto G Play (2023)',   slug: 'moto-g-play-2023',   category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto G Pure',          slug: 'moto-g-pure',        category: 'phone', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto E (2020)',        slug: 'moto-e-2020',        category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Edge 40',              slug: 'moto-edge-40',       category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Edge 30',              slug: 'moto-edge-30',       category: 'phone', release_year: 2022, is_popular: false },

  // ─── OnePlus ────────────────────────────────────────────────────────────────
  { manufacturer_slug: 'oneplus', name: 'OnePlus 12',    slug: 'oneplus-12',    category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 11',    slug: 'oneplus-11',    category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 10 Pro', slug: 'oneplus-10-pro', category: 'phone', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 9 Pro', slug: 'oneplus-9-pro', category: 'phone', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 9',     slug: 'oneplus-9',     category: 'phone', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 8 Pro', slug: 'oneplus-8-pro', category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 8',     slug: 'oneplus-8',     category: 'phone', release_year: 2020, is_popular: false },

  // ─── LG ─────────────────────────────────────────────────────────────────────
  { manufacturer_slug: 'lg', name: 'LG V60 ThinQ',  slug: 'lg-v60',  category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG V50 ThinQ',  slug: 'lg-v50',  category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG V40 ThinQ',  slug: 'lg-v40',  category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG G8 ThinQ',   slug: 'lg-g8',   category: 'phone', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG G7 ThinQ',   slug: 'lg-g7',   category: 'phone', release_year: 2018, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG K51',         slug: 'lg-k51',  category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG Stylo 6',     slug: 'lg-stylo-6', category: 'phone', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'lg', name: 'LG Stylo 5',     slug: 'lg-stylo-5', category: 'phone', release_year: 2019, is_popular: false },

  // ─── Microsoft Surface ──────────────────────────────────────────────────────
  { manufacturer_slug: 'microsoft', name: 'Surface Pro 9',     slug: 'surface-pro-9',     category: 'tablet', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'microsoft', name: 'Surface Pro 8',     slug: 'surface-pro-8',     category: 'tablet', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'microsoft', name: 'Surface Pro 7',     slug: 'surface-pro-7',     category: 'tablet', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'microsoft', name: 'Surface Laptop 5',  slug: 'surface-laptop-5',  category: 'laptop', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'microsoft', name: 'Surface Laptop 4',  slug: 'surface-laptop-4',  category: 'laptop', release_year: 2021, is_popular: false },

  // ─── Dell Laptops ─────────────────────────────────────────────────────────────
  { manufacturer_slug: 'dell', name: 'Latitude 5540',   slug: 'dell-latitude-5540',   category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Latitude 5550',   slug: 'dell-latitude-5550',   category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Latitude 7440',   slug: 'dell-latitude-7440',   category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'dell', name: 'XPS 13',          slug: 'dell-xps-13',          category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'XPS 15',          slug: 'dell-xps-15',          category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'dell', name: 'XPS 17',          slug: 'dell-xps-17',          category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Inspiron 15',     slug: 'dell-inspiron-15',     category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Inspiron 16',     slug: 'dell-inspiron-16',     category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Vostro 15',       slug: 'dell-vostro-15',       category: 'laptop', release_year: 2023, is_popular: false },

  // ─── HP Laptops ──────────────────────────────────────────────────────────────
  { manufacturer_slug: 'hp', name: 'EliteBook 840 G10',  slug: 'hp-elitebook-840-g10',  category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'hp', name: 'EliteBook 860 G10',  slug: 'hp-elitebook-860-g10',  category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'hp', name: 'ProBook 450 G10',    slug: 'hp-probook-450-g10',    category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'hp', name: 'Pavilion 15',        slug: 'hp-pavilion-15',        category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'Envy 16',            slug: 'hp-envy-16',            category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'Spectre x360 14',    slug: 'hp-spectre-x360-14',    category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'ZBook Firefly 14',   slug: 'hp-zbook-firefly-14',   category: 'laptop', release_year: 2023, is_popular: false },

  // ─── Lenovo Laptops ──────────────────────────────────────────────────────────
  { manufacturer_slug: 'lenovo', name: 'ThinkPad T14 Gen 4',         slug: 'lenovo-thinkpad-t14-gen4',        category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'ThinkPad X1 Carbon Gen 11',  slug: 'lenovo-thinkpad-x1-carbon-gen11', category: 'laptop', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'lenovo', name: 'ThinkPad L15 Gen 4',         slug: 'lenovo-thinkpad-l15-gen4',        category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'IdeaPad 5 15',               slug: 'lenovo-ideapad-5-15',             category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'Legion 5',                   slug: 'lenovo-legion-5',                 category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'Yoga 9i',                    slug: 'lenovo-yoga-9i',                  category: 'laptop', release_year: 2024, is_popular: false },

  // ─── Asus Laptops ────────────────────────────────────────────────────────────
  { manufacturer_slug: 'asus', name: 'ZenBook 14',          slug: 'asus-zenbook-14',          category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'ROG Strix G16',       slug: 'asus-rog-strix-g16',       category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'VivoBook 15',         slug: 'asus-vivobook-15',         category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'TUF Gaming A15',      slug: 'asus-tuf-gaming-a15',      category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'ProArt StudioBook',   slug: 'asus-proart-studiobook',   category: 'laptop', release_year: 2023, is_popular: false },

  // ─── Acer Laptops ────────────────────────────────────────────────────────────
  { manufacturer_slug: 'acer', name: 'Aspire 5',            slug: 'acer-aspire-5',            category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Aspire Vero',         slug: 'acer-aspire-vero',         category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Swift 5',             slug: 'acer-swift-5',             category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Nitro 5',             slug: 'acer-nitro-5',             category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Predator Helios 300', slug: 'acer-predator-helios-300', category: 'laptop', release_year: 2023, is_popular: false },

  // ─── Nintendo ────────────────────────────────────────────────────────────────
  { manufacturer_slug: 'nintendo', name: 'Nintendo Switch',      slug: 'nintendo-switch',      category: 'console', release_year: 2017, is_popular: true  },
  { manufacturer_slug: 'nintendo', name: 'Nintendo Switch OLED', slug: 'nintendo-switch-oled', category: 'console', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'nintendo', name: 'Nintendo Switch Lite', slug: 'nintendo-switch-lite', category: 'console', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'nintendo', name: 'Nintendo 3DS XL',      slug: 'nintendo-3ds-xl',      category: 'console', release_year: 2012, is_popular: false },
  { manufacturer_slug: 'nintendo', name: 'Nintendo DS Lite',     slug: 'nintendo-ds-lite',     category: 'console', release_year: 2006, is_popular: false },

  // ─── PlayStation ─────────────────────────────────────────────────────────────
  { manufacturer_slug: 'playstation', name: 'PlayStation 5',         slug: 'ps5',        category: 'console', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'playstation', name: 'PlayStation 4 Pro',     slug: 'ps4-pro',    category: 'console', release_year: 2016, is_popular: true  },
  { manufacturer_slug: 'playstation', name: 'PlayStation 4',         slug: 'ps4',        category: 'console', release_year: 2013, is_popular: true  },
  { manufacturer_slug: 'playstation', name: 'PlayStation 3',         slug: 'ps3',        category: 'console', release_year: 2006, is_popular: false },
  { manufacturer_slug: 'playstation', name: 'PlayStation Portable',  slug: 'psp',        category: 'console', release_year: 2005, is_popular: false },
  { manufacturer_slug: 'playstation', name: 'PlayStation Vita',      slug: 'ps-vita',    category: 'console', release_year: 2011, is_popular: false },

  // ─── Xbox ────────────────────────────────────────────────────────────────────
  { manufacturer_slug: 'xbox', name: 'Xbox Series X', slug: 'xbox-series-x', category: 'console', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'xbox', name: 'Xbox Series S', slug: 'xbox-series-s', category: 'console', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'xbox', name: 'Xbox One X',    slug: 'xbox-one-x',   category: 'console', release_year: 2017, is_popular: false },
  { manufacturer_slug: 'xbox', name: 'Xbox One S',    slug: 'xbox-one-s',   category: 'console', release_year: 2016, is_popular: false },
  { manufacturer_slug: 'xbox', name: 'Xbox One',      slug: 'xbox-one',     category: 'console', release_year: 2013, is_popular: false },
  { manufacturer_slug: 'xbox', name: 'Xbox 360',      slug: 'xbox-360',     category: 'console', release_year: 2005, is_popular: false },

  // ─── Steam Deck ──────────────────────────────────────────────────────────────
  { manufacturer_slug: 'steam', name: 'Steam Deck OLED', slug: 'steam-deck-oled', category: 'console', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'steam', name: 'Steam Deck',      slug: 'steam-deck',      category: 'console', release_year: 2022, is_popular: true  },

  // ─── TVs ────────────────────────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'UN43TU7000 43" LED',        slug: 'samsung-un43tu7000-43-led',        category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'UN50TU7000 50" LED',        slug: 'samsung-un50tu7000-50-led',        category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'UN55TU7000 55" LED',        slug: 'samsung-un55tu7000-55-led',        category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'QN55Q60A 55" QLED',         slug: 'samsung-qn55q60a-55-qled',         category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'QN65Q60A 65" QLED',         slug: 'samsung-qn65q60a-65-qled',         category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'QN65QN90A 65" Neo QLED',    slug: 'samsung-qn65qn90a-65-neo-qled',    category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'QN85QN90A 85" Neo QLED',    slug: 'samsung-qn85qn90a-85-neo-qled',    category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'QN65QN90B 65" Neo QLED',    slug: 'samsung-qn65qn90b-65-neo-qled',    category: 'tv', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'QN77S95C 77" OLED',         slug: 'samsung-qn77s95c-77-oled',         category: 'tv', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'PN60F5300 60" Plasma',      slug: 'samsung-pn60f5300-60-plasma',      category: 'tv', release_year: 2013, is_popular: false },

  { manufacturer_slug: 'lg', name: '43UP7000 43" LED',      slug: 'lg-43up7000-43-led',      category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'lg', name: '50UP7000 50" LED',      slug: 'lg-50up7000-50-led',      category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'lg', name: '55UP8000 55" LED',      slug: 'lg-55up8000-55-led',      category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'lg', name: '65UP8000 65" LED',      slug: 'lg-65up8000-65-led',      category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'lg', name: '65NANO90 65" NanoCell LED', slug: 'lg-65nano90-65-nanocell-led', category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'lg', name: 'OLED55CX 55" OLED',     slug: 'lg-oled55cx-55-oled',     category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'lg', name: 'OLED65C1 65" OLED',     slug: 'lg-oled65c1-65-oled',     category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'lg', name: 'OLED65C2 65" OLED',     slug: 'lg-oled65c2-65-oled',     category: 'tv', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'lg', name: 'OLED77C3 77" OLED',     slug: 'lg-oled77c3-77-oled',     category: 'tv', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'lg', name: '50PN4500 50" Plasma',   slug: 'lg-50pn4500-50-plasma',   category: 'tv', release_year: 2013, is_popular: false },

  { manufacturer_slug: 'sony', name: 'XBR-43X800H 43" LED', slug: 'sony-xbr-43x800h-43-led', category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'sony', name: 'XBR-55X900H 55" LED', slug: 'sony-xbr-55x900h-55-led', category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XBR-65X900H 65" LED', slug: 'sony-xbr-65x900h-65-led', category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XR-55X90J 55" LED',   slug: 'sony-xr-55x90j-55-led',   category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XR-65X90J 65" LED',   slug: 'sony-xr-65x90j-65-led',   category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XR-55A80J 55" OLED',  slug: 'sony-xr-55a80j-55-oled',  category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XR-65A80J 65" OLED',  slug: 'sony-xr-65a80j-65-oled',  category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XR-65X90K 65" LED',   slug: 'sony-xr-65x90k-65-led',   category: 'tv', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'sony', name: 'XR-85X90K 85" LED',   slug: 'sony-xr-85x90k-85-led',   category: 'tv', release_year: 2022, is_popular: false },
  { manufacturer_slug: 'sony', name: 'XR-77A80L 77" OLED',  slug: 'sony-xr-77a80l-77-oled',  category: 'tv', release_year: 2023, is_popular: false },

  { manufacturer_slug: 'vizio', name: 'V405-H19 40" LED',   slug: 'vizio-v405-h19-40-led',   category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'vizio', name: 'V505-J09 50" LED',   slug: 'vizio-v505-j09-50-led',   category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'vizio', name: 'V555-J01 55" LED',   slug: 'vizio-v555-j01-55-led',   category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'vizio', name: 'V655-J09 65" LED',   slug: 'vizio-v655-j09-65-led',   category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'vizio', name: 'M50Q7-H1 50" QLED',  slug: 'vizio-m50q7-h1-50-qled',  category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'vizio', name: 'M55Q7-J01 55" QLED', slug: 'vizio-m55q7-j01-55-qled', category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'vizio', name: 'M65Q7-J01 65" QLED', slug: 'vizio-m65q7-j01-65-qled', category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'vizio', name: 'P65Q9-H1 65" QLED',  slug: 'vizio-p65q9-h1-65-qled',  category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'vizio', name: 'P75Q9-J01 75" QLED', slug: 'vizio-p75q9-j01-75-qled', category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'vizio', name: 'OLED55-H1 55" OLED', slug: 'vizio-oled55-h1-55-oled', category: 'tv', release_year: 2020, is_popular: false },

  { manufacturer_slug: 'hisense', name: '43A6G 43" LED',             slug: 'hisense-43a6g-43-led',             category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'hisense', name: '50A6G 50" LED',             slug: 'hisense-50a6g-50-led',             category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '55A6G 55" LED',             slug: 'hisense-55a6g-55-led',             category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '65A6G 65" LED',             slug: 'hisense-65a6g-65-led',             category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '55U6G 55" QLED',            slug: 'hisense-55u6g-55-qled',            category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '65U6G 65" QLED',            slug: 'hisense-65u6g-65-qled',            category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '55U7G 55" QLED',            slug: 'hisense-55u7g-55-qled',            category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'hisense', name: '65U8G 65" QLED',            slug: 'hisense-65u8g-65-qled',            category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '65U8H 65" Mini-LED QLED',   slug: 'hisense-65u8h-65-mini-led-qled',   category: 'tv', release_year: 2022, is_popular: true  },
  { manufacturer_slug: 'hisense', name: '75U8K 75" Mini-LED QLED',   slug: 'hisense-75u8k-75-mini-led-qled',   category: 'tv', release_year: 2023, is_popular: false },

  { manufacturer_slug: 'tcl', name: '40S325 40" LED',  slug: 'tcl-40s325-40-led',  category: 'tv', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'tcl', name: '43S435 43" LED',  slug: 'tcl-43s435-43-led',  category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'tcl', name: '50S435 50" LED',  slug: 'tcl-50s435-50-led',  category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'tcl', name: '55S435 55" LED',  slug: 'tcl-55s435-55-led',  category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'tcl', name: '65S435 65" LED',  slug: 'tcl-65s435-65-led',  category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'tcl', name: '55R635 55" QLED', slug: 'tcl-55r635-55-qled', category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'tcl', name: '65R635 65" QLED', slug: 'tcl-65r635-65-qled', category: 'tv', release_year: 2020, is_popular: true  },
  { manufacturer_slug: 'tcl', name: '65R646 65" QLED', slug: 'tcl-65r646-65-qled', category: 'tv', release_year: 2021, is_popular: true  },
  { manufacturer_slug: 'tcl', name: '75R655 75" QLED', slug: 'tcl-75r655-75-qled', category: 'tv', release_year: 2022, is_popular: false },

  { manufacturer_slug: 'philips', name: '43PFL5604/F7 43" LED', slug: 'philips-43pfl5604-f7-43-led', category: 'tv', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'philips', name: '50PFL5604/F7 50" LED', slug: 'philips-50pfl5604-f7-50-led', category: 'tv', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'philips', name: '55PFL5604/F7 55" LED', slug: 'philips-55pfl5604-f7-55-led', category: 'tv', release_year: 2019, is_popular: true  },
  { manufacturer_slug: 'philips', name: '65PFL5504/F7 65" LED', slug: 'philips-65pfl5504-f7-65-led', category: 'tv', release_year: 2019, is_popular: false },
  { manufacturer_slug: 'philips', name: '50PFL5704/F7 50" LED', slug: 'philips-50pfl5704-f7-50-led', category: 'tv', release_year: 2020, is_popular: false },
  { manufacturer_slug: 'philips', name: '55PFL5756/F7 55" LED', slug: 'philips-55pfl5756-f7-55-led', category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'philips', name: '65PFL5766/F7 65" LED', slug: 'philips-65pfl5766-f7-65-led', category: 'tv', release_year: 2021, is_popular: false },
  { manufacturer_slug: 'philips', name: '65OLED706 65" OLED',   slug: 'philips-65oled706-65-oled',   category: 'tv', release_year: 2021, is_popular: false },

  // ═══════════════════════════════════════════════════════════════════════════
  // 2024 / 2025 ADDITIONS — keeps the seeder current with shipping flagships.
  // INSERT OR IGNORE in the runner makes appending here safe across every
  // existing tenant DB on next server boot.
  // ═══════════════════════════════════════════════════════════════════════════

  // ─── Apple iPhone (2025) ───────────────────────────────────────────────────
  { manufacturer_slug: 'apple', name: 'iPhone 17 Pro Max',  slug: 'iphone-17-pro-max', category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 17 Pro',      slug: 'iphone-17-pro',     category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 17 Plus',     slug: 'iphone-17-plus',    category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 17',          slug: 'iphone-17',         category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone Air',         slug: 'iphone-air',        category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPhone 16e',         slug: 'iphone-16e',        category: 'phone', release_year: 2025, is_popular: true  },

  // ─── Apple iPad (M4 / 2024-2025) ───────────────────────────────────────────
  { manufacturer_slug: 'apple', name: 'iPad Pro 13" (M4)',     slug: 'ipad-pro-13-m4',     category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Pro 11" (M4)',     slug: 'ipad-pro-11-m4',     category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Air 13" (M2)',     slug: 'ipad-air-13-m2',     category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad Air 11" (M2)',     slug: 'ipad-air-11-m2',     category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad mini (7th Gen)',   slug: 'ipad-mini-7th',      category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iPad (11th Gen)',       slug: 'ipad-11th',          category: 'tablet', release_year: 2025, is_popular: true  },

  // ─── Apple MacBook / Mac (M4 / 2024-2025) ──────────────────────────────────
  { manufacturer_slug: 'apple', name: 'MacBook Pro 16" (M4 Max)', slug: 'macbook-pro-16-m4-max', category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 16" (M4 Pro)', slug: 'macbook-pro-16-m4-pro', category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 14" (M4 Max)', slug: 'macbook-pro-14-m4-max', category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 14" (M4 Pro)', slug: 'macbook-pro-14-m4-pro', category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Pro 14" (M4)',     slug: 'macbook-pro-14-m4',     category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 15" (M4)',     slug: 'macbook-air-15-m4',     category: 'laptop', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 13" (M4)',     slug: 'macbook-air-13-m4',     category: 'laptop', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 15" (M3)',     slug: 'macbook-air-15-m3',     category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'MacBook Air 13" (M3)',     slug: 'macbook-air-13-m3',     category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'apple', name: 'iMac (M4)',                slug: 'imac-m4',                category: 'desktop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'apple', name: 'Mac mini (M4)',            slug: 'mac-mini-m4',            category: 'desktop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'apple', name: 'Mac mini (M4 Pro)',        slug: 'mac-mini-m4-pro',        category: 'desktop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'apple', name: 'Mac Studio (M4 Max)',      slug: 'mac-studio-m4-max',      category: 'desktop', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'apple', name: 'Mac Studio (M3 Ultra)',    slug: 'mac-studio-m3-ultra',    category: 'desktop', release_year: 2025, is_popular: false },

  // ─── Samsung Galaxy S (2024 FE / 2025) ─────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy S25 Ultra',  slug: 'galaxy-s25-ultra',  category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S25+',       slug: 'galaxy-s25-plus',   category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S25',        slug: 'galaxy-s25',        category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy S25 Edge',   slug: 'galaxy-s25-edge',   category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy S24 FE',     slug: 'galaxy-s24-fe',     category: 'phone', release_year: 2024, is_popular: true  },

  // ─── Samsung Galaxy A (2025) ───────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy A56',        slug: 'galaxy-a56',        category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A36',        slug: 'galaxy-a36',        category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy A26',        slug: 'galaxy-a26',        category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy A16',        slug: 'galaxy-a16',        category: 'phone', release_year: 2024, is_popular: false },

  // ─── Samsung Galaxy Z foldables (2024 / 2025) ──────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Fold 7',   slug: 'galaxy-z-fold-7',   category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Flip 7',   slug: 'galaxy-z-flip-7',   category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Flip 7 FE', slug: 'galaxy-z-flip-7-fe', category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Fold 6',   slug: 'galaxy-z-fold-6',   category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Z Flip 6',   slug: 'galaxy-z-flip-6',   category: 'phone', release_year: 2024, is_popular: true  },

  // ─── Samsung Tablets (2024) ────────────────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S10 Ultra', slug: 'galaxy-tab-s10-ultra', category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S10+',      slug: 'galaxy-tab-s10-plus',  category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S10 FE+',   slug: 'galaxy-tab-s10-fe-plus', category: 'tablet', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'samsung', name: 'Galaxy Tab S10 FE',    slug: 'galaxy-tab-s10-fe',    category: 'tablet', release_year: 2025, is_popular: false },

  // ─── Google Pixel (2025) ───────────────────────────────────────────────────
  { manufacturer_slug: 'google', name: 'Pixel 10 Pro XL',    slug: 'pixel-10-pro-xl',   category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 10 Pro',       slug: 'pixel-10-pro',      category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 10 Pro Fold',  slug: 'pixel-10-pro-fold', category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 10',           slug: 'pixel-10',          category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'google', name: 'Pixel 9 Pro Fold',   slug: 'pixel-9-pro-fold',  category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'google', name: 'Pixel 9a',           slug: 'pixel-9a',          category: 'phone', release_year: 2025, is_popular: true  },

  // ─── OnePlus (2024 / 2025) ─────────────────────────────────────────────────
  { manufacturer_slug: 'oneplus', name: 'OnePlus 13',        slug: 'oneplus-13',        category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 13R',       slug: 'oneplus-13r',       category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 13T',       slug: 'oneplus-13t',       category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus 12R',       slug: 'oneplus-12r',       category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus Open',      slug: 'oneplus-open',      category: 'phone', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus Pad',       slug: 'oneplus-pad',       category: 'tablet', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'oneplus', name: 'OnePlus Pad 2',     slug: 'oneplus-pad-2',     category: 'tablet', release_year: 2024, is_popular: false },

  // ─── Motorola (2024 / 2025) ────────────────────────────────────────────────
  { manufacturer_slug: 'motorola', name: 'Moto G Power (2025)',  slug: 'moto-g-power-2025',  category: 'phone', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'motorola', name: 'Moto G Stylus (2025)', slug: 'moto-g-stylus-2025', category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Moto G (2025)',        slug: 'moto-g-2025',        category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Razr 50 Ultra',        slug: 'moto-razr-50-ultra', category: 'phone', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'motorola', name: 'Razr 50',              slug: 'moto-razr-50',       category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Edge 50 Ultra',        slug: 'moto-edge-50-ultra', category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'motorola', name: 'Edge 50 Pro',          slug: 'moto-edge-50-pro',   category: 'phone', release_year: 2024, is_popular: false },

  // ─── Xiaomi (2024 / 2025) ──────────────────────────────────────────────────
  { manufacturer_slug: 'xiaomi', name: 'Xiaomi 15 Ultra',    slug: 'xiaomi-15-ultra',   category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Xiaomi 15 Pro',      slug: 'xiaomi-15-pro',     category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Xiaomi 15',          slug: 'xiaomi-15',         category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Xiaomi 14 Ultra',    slug: 'xiaomi-14-ultra',   category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Xiaomi 14',          slug: 'xiaomi-14',         category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Redmi Note 14 Pro+', slug: 'redmi-note-14-pro-plus', category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Redmi Note 14 Pro',  slug: 'redmi-note-14-pro', category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Redmi Note 14',      slug: 'redmi-note-14',     category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'POCO X7 Pro',        slug: 'poco-x7-pro',       category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'POCO F7 Pro',        slug: 'poco-f7-pro',       category: 'phone', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Pad 7 Pro',          slug: 'xiaomi-pad-7-pro',  category: 'tablet', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'xiaomi', name: 'Pad 7',              slug: 'xiaomi-pad-7',      category: 'tablet', release_year: 2025, is_popular: false },

  // ─── realme (2024 / 2025) ──────────────────────────────────────────────────
  { manufacturer_slug: 'realme', name: 'realme GT 7 Pro',    slug: 'realme-gt-7-pro',   category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'realme', name: 'realme GT 6',        slug: 'realme-gt-6',       category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'realme', name: 'realme 13 Pro+',     slug: 'realme-13-pro-plus', category: 'phone', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'realme', name: 'realme 12 Pro+',     slug: 'realme-12-pro-plus', category: 'phone', release_year: 2024, is_popular: false },

  // ─── Microsoft Surface (2024) ──────────────────────────────────────────────
  { manufacturer_slug: 'microsoft', name: 'Surface Pro 11',    slug: 'surface-pro-11',    category: 'tablet', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'microsoft', name: 'Surface Pro 10',    slug: 'surface-pro-10',    category: 'tablet', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'microsoft', name: 'Surface Laptop 7',  slug: 'surface-laptop-7',  category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'microsoft', name: 'Surface Laptop 6',  slug: 'surface-laptop-6',  category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'microsoft', name: 'Surface Laptop Studio 2', slug: 'surface-laptop-studio-2', category: 'laptop', release_year: 2023, is_popular: false },
  { manufacturer_slug: 'microsoft', name: 'Surface Laptop Go 3', slug: 'surface-laptop-go-3', category: 'laptop', release_year: 2023, is_popular: false },

  // ─── Dell (2024 / 2025) ────────────────────────────────────────────────────
  { manufacturer_slug: 'dell', name: 'XPS 13 (9350)',        slug: 'dell-xps-13-9350',  category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'dell', name: 'XPS 14 (9440)',        slug: 'dell-xps-14-9440',  category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'dell', name: 'XPS 16 (9640)',        slug: 'dell-xps-16-9640',  category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Latitude 7450',        slug: 'dell-latitude-7450', category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Latitude 5450',        slug: 'dell-latitude-5450', category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Pro 14 Plus',          slug: 'dell-pro-14-plus',   category: 'laptop', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'dell', name: 'Pro 14 Premium',       slug: 'dell-pro-14-premium', category: 'laptop', release_year: 2025, is_popular: false },

  // ─── HP (2024 / 2025) ──────────────────────────────────────────────────────
  { manufacturer_slug: 'hp', name: 'EliteBook X G1i',          slug: 'hp-elitebook-x-g1i',          category: 'laptop', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'hp', name: 'EliteBook 1040 G11',       slug: 'hp-elitebook-1040-g11',       category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'EliteBook 840 G11',        slug: 'hp-elitebook-840-g11',        category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'OmniBook X 14',            slug: 'hp-omnibook-x-14',            category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'Spectre x360 16 (2024)',   slug: 'hp-spectre-x360-16-2024',     category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'hp', name: 'OmniBook Ultra Flip 14',   slug: 'hp-omnibook-ultra-flip-14',   category: 'laptop', release_year: 2025, is_popular: false },

  // ─── Lenovo (2024 / 2025) ──────────────────────────────────────────────────
  { manufacturer_slug: 'lenovo', name: 'ThinkPad X1 Carbon Gen 12', slug: 'lenovo-thinkpad-x1-carbon-gen12', category: 'laptop', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'lenovo', name: 'ThinkPad X1 Carbon Gen 13', slug: 'lenovo-thinkpad-x1-carbon-gen13', category: 'laptop', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'lenovo', name: 'ThinkPad T14 Gen 5',        slug: 'lenovo-thinkpad-t14-gen5',        category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'ThinkPad P1 Gen 7',         slug: 'lenovo-thinkpad-p1-gen7',         category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'Yoga Slim 7x',              slug: 'lenovo-yoga-slim-7x',             category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'IdeaPad Slim 5x',           slug: 'lenovo-ideapad-slim-5x',          category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'Legion Pro 7i Gen 9',       slug: 'lenovo-legion-pro-7i-gen9',       category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'lenovo', name: 'ThinkBook 13x Gen 4',       slug: 'lenovo-thinkbook-13x-gen4',       category: 'laptop', release_year: 2024, is_popular: false },

  // ─── Asus (2024 / 2025) ────────────────────────────────────────────────────
  { manufacturer_slug: 'asus', name: 'Zenbook S 14',             slug: 'asus-zenbook-s14',            category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'Zenbook A14',              slug: 'asus-zenbook-a14',            category: 'laptop', release_year: 2025, is_popular: false },
  { manufacturer_slug: 'asus', name: 'ROG Zephyrus G16',         slug: 'asus-rog-zephyrus-g16',       category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'ROG Strix Scar 18',        slug: 'asus-rog-strix-scar-18',      category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'asus', name: 'ProArt P16',               slug: 'asus-proart-p16',             category: 'laptop', release_year: 2024, is_popular: false },

  // ─── Acer (2024 / 2025) ────────────────────────────────────────────────────
  { manufacturer_slug: 'acer', name: 'Swift 14 AI',              slug: 'acer-swift-14-ai',            category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Swift Go 14',              slug: 'acer-swift-go-14',            category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Predator Helios 18 (2024)', slug: 'acer-predator-helios-18-2024', category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Predator Triton 14',       slug: 'acer-predator-triton-14',     category: 'laptop', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'acer', name: 'Aspire Go 15',             slug: 'acer-aspire-go-15',           category: 'laptop', release_year: 2024, is_popular: false },

  // ─── Game consoles (2024 / 2025) ───────────────────────────────────────────
  { manufacturer_slug: 'nintendo',    name: 'Nintendo Switch 2',     slug: 'nintendo-switch-2',     category: 'console', release_year: 2025, is_popular: true  },
  { manufacturer_slug: 'playstation', name: 'PlayStation 5 Pro',     slug: 'ps5-pro',               category: 'console', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'playstation', name: 'PlayStation 5 Slim',    slug: 'ps5-slim',              category: 'console', release_year: 2023, is_popular: true  },
  { manufacturer_slug: 'steam',       name: 'Steam Deck OLED LE',    slug: 'steam-deck-oled-le',    category: 'console', release_year: 2024, is_popular: false },

  // ─── Recent flagship TVs (2023-2025) ───────────────────────────────────────
  { manufacturer_slug: 'samsung', name: 'QN90D 65" Neo QLED 4K',  slug: 'samsung-qn90d-65-neo-qled', category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'S95D 65" QD-OLED 4K',    slug: 'samsung-s95d-65-qd-oled',   category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'samsung', name: 'S90D 55" OLED 4K',       slug: 'samsung-s90d-55-oled',      category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'lg',      name: 'OLED65G4 65" OLED evo',  slug: 'lg-oled65g4-65-oled-evo',   category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'lg',      name: 'OLED65C4 65" OLED',      slug: 'lg-oled65c4-65-oled',       category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'lg',      name: 'QNED85 75" QNED',        slug: 'lg-qned85-75-qned',         category: 'tv', release_year: 2024, is_popular: false },
  { manufacturer_slug: 'sony',    name: 'Bravia 9 65" Mini-LED',  slug: 'sony-bravia-9-65-mini-led', category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'sony',    name: 'Bravia 8 65" OLED',      slug: 'sony-bravia-8-65-oled',     category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'tcl',     name: 'QM8 65" Mini-LED QLED',  slug: 'tcl-qm8-65-mini-led-qled',  category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'hisense', name: 'U8N 65" Mini-LED ULED',  slug: 'hisense-u8n-65-mini-led',   category: 'tv', release_year: 2024, is_popular: true  },
  { manufacturer_slug: 'hisense', name: 'U7N 65" ULED',           slug: 'hisense-u7n-65-uled',       category: 'tv', release_year: 2024, is_popular: false },
];
