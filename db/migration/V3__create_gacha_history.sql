create table gacha_pity_states (
    account_id uuid not null references player_accounts(id) on delete restrict,
    banner_code varchar(60) not null,
    hero_pity integer not null default 0 check (hero_pity >= 0),
    legendary_pity integer not null default 0 check (legendary_pity >= 0),
    version bigint not null default 0 check (version >= 0),
    updated_at timestamptz not null default now(),
    primary key (account_id, banner_code)
);

create table gacha_draws (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    request_id uuid not null,
    request_hash char(64) not null check (request_hash ~ '^[0-9a-f]{64}$'),
    banner_code varchar(60) not null,
    payment_asset_type varchar(20) not null check (payment_asset_type in ('CURRENCY', 'ITEM')),
    payment_asset_code varchar(80) not null,
    payment_amount bigint not null check (payment_amount > 0),
    draw_count integer not null check (draw_count between 1 and 10),
    response_payload jsonb not null,
    created_at timestamptz not null default now(),
    unique (account_id, request_id)
);

create index gacha_draws_account_created_idx
    on gacha_draws (account_id, created_at desc, id desc);

create table gacha_draw_results (
    draw_id uuid not null references gacha_draws(id) on delete restrict,
    result_index integer not null check (result_index between 0 and 9),
    equipment_id uuid not null references player_equipment(id) on delete restrict,
    equipment_code varchar(80) not null,
    grade varchar(30) not null,
    chroma boolean not null default false,
    primary key (draw_id, result_index),
    unique (equipment_id)
);

create index gacha_draw_results_equipment_code_idx
    on gacha_draw_results (equipment_code);
