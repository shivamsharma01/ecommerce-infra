create table if not exists cart_items (
  id uuid primary key,
  user_id uuid not null,
  product_id varchar(64) not null,
  quantity integer not null check (quantity > 0),
  updated_at timestamptz not null default now()
);

create unique index if not exists uk_cart_user_product on cart_items(user_id, product_id);
