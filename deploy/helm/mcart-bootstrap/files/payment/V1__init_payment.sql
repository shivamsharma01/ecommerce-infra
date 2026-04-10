create table if not exists payments (
  payment_id uuid primary key,
  order_id varchar(128) not null,
  amount bigint not null check (amount > 0),
  status varchar(16) not null,
  created_at timestamptz not null default now()
);
