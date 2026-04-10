create table if not exists inventory (
  product_id varchar(64) primary key,
  available_qty integer not null check (available_qty >= 0),
  updated_at timestamptz not null default now()
);
