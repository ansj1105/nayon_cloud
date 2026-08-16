create table player_wallets (
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    currency_code varchar(40) not null,
    balance bigint not null default 0 check (balance >= 0),
    version bigint not null default 0 check (version >= 0),
    updated_at timestamptz not null default now(),
    primary key (account_id, currency_code)
);

create table player_items (
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    item_code varchar(80) not null,
    quantity bigint not null default 0 check (quantity >= 0),
    version bigint not null default 0 check (version >= 0),
    updated_at timestamptz not null default now(),
    primary key (account_id, item_code)
);

create table player_equipment (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    equipment_code varchar(80) not null,
    grade varchar(30) not null,
    level integer not null default 1 check (level >= 1),
    locked boolean not null default false,
    source_type varchar(40) not null,
    source_id uuid not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index player_equipment_account_created_idx
    on player_equipment (account_id, created_at desc);

create index player_equipment_source_idx
    on player_equipment (source_type, source_id);

create table economy_ledger (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    asset_type varchar(20) not null
        check (asset_type in ('CURRENCY', 'ITEM')),
    asset_code varchar(80) not null,
    delta bigint not null,
    balance_before bigint not null check (balance_before >= 0),
    balance_after bigint not null check (balance_after >= 0),
    reason_code varchar(60) not null,
    reference_type varchar(40) not null,
    reference_id uuid not null,
    request_id uuid not null,
    created_at timestamptz not null default now(),
    check (balance_after = balance_before + delta)
);

create index economy_ledger_account_created_idx
    on economy_ledger (account_id, created_at desc);

create index economy_ledger_reference_idx
    on economy_ledger (reference_type, reference_id);

create table economy_bootstraps (
    account_id uuid primary key
        references player_accounts(id) on delete restrict,
    request_id uuid not null unique,
    request_hash char(64) not null check (request_hash ~ '^[0-9a-f]{64}$'),
    response_payload jsonb not null,
    created_at timestamptz not null default now()
);
