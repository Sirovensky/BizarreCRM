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
  category: 'phone' | 'tablet' | 'laptop' | 'console' | 'other';
  release_year?: number;
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
];
