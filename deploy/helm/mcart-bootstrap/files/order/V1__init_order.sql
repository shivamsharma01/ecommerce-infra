create table if not exists orders (
  order_id uuid primary key,
  user_id uuid not null,
  total_amount bigint not null check (total_amount > 0),
  status varchar(16) not null,
  created_at timestamptz not null default now()
);

create table if not exists order_items (
  id uuid primary key,
  order_id uuid not null references orders(order_id) on delete cascade,
  product_id varchar(64) not null,
  quantity integer not null check (quantity > 0),
  unit_price bigint not null check (unit_price >= 0),
  line_total bigint not null check (line_total >= 0)
);

create index if not exists ix_orders_user_created_at on orders(user_id, created_at desc);
create index if not exists ix_order_items_order_id on order_items(order_id);
