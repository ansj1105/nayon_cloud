create table store_offers (
    id uuid primary key,
    offer_code varchar(64) not null unique,
    display_order integer not null,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (offer_code ~ '^[a-z][a-z0-9_]{2,63}$'),
    check (display_order >= 0)
);

create table store_products (
    id uuid primary key,
    offer_id uuid not null references store_offers(id) on delete restrict,
    platform varchar(20) not null check (platform in ('GOOGLE_PLAY')),
    store_product_id varchar(200) not null,
    product_type varchar(20) not null check (product_type in ('ONE_TIME')),
    active boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (platform, store_product_id),
    check (char_length(trim(store_product_id)) > 0)
);

create unique index store_products_one_active_offer_platform_idx
    on store_products (offer_id, platform)
    where active;

create table store_product_versions (
    id uuid primary key,
    product_id uuid not null references store_products(id) on delete restrict,
    version integer not null,
    reward_asset_type varchar(20) not null
        check (reward_asset_type in ('CURRENCY')),
    reward_asset_code varchar(40) not null,
    reward_amount bigint not null,
    valid_from timestamptz not null,
    valid_until timestamptz,
    active boolean not null default false,
    created_at timestamptz not null default now(),
    unique (product_id, version),
    unique (id, product_id),
    check (version > 0),
    check (reward_asset_code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
    check (reward_amount > 0),
    check (valid_until is null or valid_until > valid_from)
);

create unique index store_product_versions_one_active_product_idx
    on store_product_versions (product_id)
    where active;

create index store_product_versions_validity_idx
    on store_product_versions (product_id, active, valid_from, valid_until);

create table store_purchase_receipts (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    request_id uuid not null unique,
    request_hash char(64) not null,
    platform varchar(20) not null check (platform in ('GOOGLE_PLAY')),
    store_product_id varchar(200) not null,
    purchase_token text not null,
    purchase_token_hash char(64) not null unique,
    state varchar(24) not null check (
        state in ('PENDING_VERIFICATION', 'REJECTED', 'GRANTED')),
    product_id uuid not null references store_products(id) on delete restrict,
    product_version_id uuid,
    google_order_id varchar(200),
    google_purchase_time timestamptz,
    verified_at timestamptz,
    reward_asset_code varchar(40),
    reward_amount bigint,
    total_asset_balance bigint,
    rejection_code varchar(64),
    last_failure_code varchar(64),
    verification_attempts integer not null default 0,
    granted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint store_purchase_receipts_version_product_fk
        foreign key (product_version_id, product_id)
        references store_product_versions(id, product_id) on delete restrict,
    check (char_length(trim(store_product_id)) > 0),
    check (char_length(trim(purchase_token)) > 0),
    check (request_hash ~ '^[0-9a-f]{64}$'),
    check (purchase_token_hash ~ '^[0-9a-f]{64}$'),
    check (verification_attempts >= 0),
    check (
        (state = 'PENDING_VERIFICATION'
            and product_version_id is null
            and granted_at is null)
        or (state = 'REJECTED'
            and rejection_code is not null
            and granted_at is null)
        or (state = 'GRANTED'
            and product_id is not null
            and product_version_id is not null
            and verified_at is not null
            and reward_asset_code is not null
            and reward_amount > 0
            and total_asset_balance >= 0
            and granted_at is not null)
    )
);

create index store_purchase_receipts_account_created_idx
    on store_purchase_receipts (account_id, created_at desc);

insert into store_offers(id, offer_code, display_order)
values
    ('00000000-0000-0000-0000-000000009101', 'diamond_100', 10),
    ('00000000-0000-0000-0000-000000009102', 'diamond_600', 20),
    ('00000000-0000-0000-0000-000000009103', 'diamond_1500', 30),
    ('00000000-0000-0000-0000-000000009104', 'diamond_3000', 40),
    ('00000000-0000-0000-0000-000000009105', 'diamond_7000', 50),
    ('00000000-0000-0000-0000-000000009106', 'diamond_15000', 60);

comment on table store_offers is
    '앱과 API가 공유하는 안정적인 판매 제안 코드';
comment on table store_products is
    '판매 제안과 플랫폼 스토어 상품 ID의 변경 가능한 매핑';
comment on table store_product_versions is
    'Google 구매 시각 기준으로 선택하는 불변 보상 버전';
comment on table store_purchase_receipts is
    'Google 검증과 정확히 1회 원장 지급을 위한 계정별 구매 상태';
