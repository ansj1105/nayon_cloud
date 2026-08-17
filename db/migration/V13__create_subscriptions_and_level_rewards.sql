alter table store_products
    drop constraint store_products_product_type_check;
alter table store_products
    add constraint store_products_product_type_check
        check (product_type in ('ONE_TIME', 'SUBSCRIPTION'));

alter table store_product_versions
    drop constraint store_product_versions_fulfillment_type_check;
alter table store_product_versions
    add constraint store_product_versions_fulfillment_type_check
        check (fulfillment_type in (
            'DIRECT_CURRENCY', 'LIMITED_BENEFIT', 'SUBSCRIPTION'));

alter table store_product_versions
    drop constraint store_product_versions_fulfillment_payload_check;
alter table store_product_versions
    add constraint store_product_versions_fulfillment_payload_check check (
        (fulfillment_type = 'DIRECT_CURRENCY'
            and reward_asset_type = 'CURRENCY'
            and reward_asset_code is not null
            and reward_asset_code ~ '^[A-Z][A-Z0-9_]{1,39}$'
            and reward_amount > 0)
        or (fulfillment_type in ('LIMITED_BENEFIT', 'SUBSCRIPTION')
            and reward_asset_type is null
            and reward_asset_code is null
            and reward_amount is null)
    );

insert into store_offers(id, offer_code, display_order)
values
    ('00000000-0000-0000-0000-000000013801', 'monthly_growth', 3010),
    ('00000000-0000-0000-0000-000000013802', 'monthly_advanced', 3020);

create table subscription_plans (
    id uuid primary key,
    plan_code varchar(32) not null unique,
    offer_id uuid not null unique
        references store_offers(id) on delete restrict,
    reward_track_code varchar(16) not null unique
        check (reward_track_code in ('PREMIUM', 'ROYAL')),
    active boolean not null default true,
    valid_from timestamptz not null,
    valid_until timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (plan_code in ('MONTHLY_GROWTH', 'MONTHLY_ADVANCED')),
    check (valid_until is null or valid_until > valid_from)
);

insert into subscription_plans(
    id, plan_code, offer_id, reward_track_code, valid_from)
values
    ('00000000-0000-0000-0000-000000013811', 'MONTHLY_GROWTH',
     '00000000-0000-0000-0000-000000013801', 'PREMIUM',
     '2026-08-18 00:00:00+09'),
    ('00000000-0000-0000-0000-000000013812', 'MONTHLY_ADVANCED',
     '00000000-0000-0000-0000-000000013802', 'ROYAL',
     '2026-08-18 00:00:00+09');

create table subscription_benefit_versions (
    id uuid primary key,
    plan_id uuid not null
        references subscription_plans(id) on delete restrict,
    version integer not null,
    benefit_code varchar(40) not null check (benefit_code in (
        'INITIAL_DIAMOND', 'DAILY_DIAMOND', 'SKILL_REFRESH_COUNT',
        'REVIVE_COUNT', 'MAX_ENERGY', 'GOLD_BONUS_BPS',
        'BATTLE_SPEED_UNLOCK', 'REWARDED_AD_SKIP')),
    benefit_value bigint not null check (benefit_value > 0),
    valid_from timestamptz not null,
    valid_until timestamptz,
    active boolean not null default false,
    created_at timestamptz not null default now(),
    unique (plan_id, version, benefit_code),
    unique (id, plan_id),
    check (version > 0),
    check (valid_until is null or valid_until > valid_from),
    check (benefit_code not in ('BATTLE_SPEED_UNLOCK', 'REWARDED_AD_SKIP')
        or benefit_value = 1)
);

create unique index subscription_benefit_one_active_idx
    on subscription_benefit_versions(plan_id, benefit_code)
    where active;

create table player_subscriptions (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    plan_id uuid not null
        references subscription_plans(id) on delete restrict,
    purchase_token text not null,
    purchase_token_hash char(64) not null unique,
    linked_purchase_token_hash char(64),
    state varchar(24) not null check (state in (
        'PENDING', 'ACTIVE', 'CANCELED', 'GRACE_PERIOD',
        'ON_HOLD', 'PAUSED', 'EXPIRED', 'REVOKED')),
    started_at timestamptz,
    expires_at timestamptz,
    auto_renewing boolean not null default false,
    acknowledgement_state varchar(20) not null check (
        acknowledgement_state in ('PENDING', 'ACKNOWLEDGED')),
    google_order_id varchar(200),
    last_verified_at timestamptz,
    last_failure_code varchar(64),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (account_id, plan_id),
    unique (id, account_id),
    check (char_length(trim(purchase_token)) > 0),
    check (purchase_token_hash ~ '^[0-9a-f]{64}$'),
    check (linked_purchase_token_hash is null
        or linked_purchase_token_hash ~ '^[0-9a-f]{64}$'),
    check (expires_at is null or started_at is null or expires_at > started_at),
    check (state = 'PENDING'
        or (started_at is not null and expires_at is not null
            and last_verified_at is not null))
);

create index player_subscriptions_account_state_idx
    on player_subscriptions(account_id, state, expires_at);

create table subscription_verification_requests (
    request_id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    subscription_id uuid not null,
    request_hash char(64) not null,
    store_product_id varchar(200) not null,
    purchase_token text not null,
    purchase_token_hash char(64) not null,
    state varchar(16) not null
        check (state in ('PENDING', 'COMPLETED', 'REJECTED')),
    response_payload jsonb,
    failure_code varchar(64),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint subscription_verification_subscription_owner_fk
        foreign key (subscription_id, account_id)
        references player_subscriptions(id, account_id) on delete restrict,
    check (request_hash ~ '^[0-9a-f]{64}$'),
    check (char_length(trim(store_product_id)) > 0),
    check (char_length(trim(purchase_token)) > 0),
    check (purchase_token_hash ~ '^[0-9a-f]{64}$'),
    check ((state = 'PENDING' and response_payload is null)
        or (state = 'COMPLETED' and response_payload is not null
            and failure_code is null)
        or (state = 'REJECTED' and failure_code is not null))
);

create index subscription_verification_account_created_idx
    on subscription_verification_requests(account_id, created_at desc);

create index subscription_verification_token_idx
    on subscription_verification_requests(purchase_token_hash);

create table google_play_rtdn_events (
    message_id varchar(200) primary key,
    package_name varchar(200) not null,
    notification_type integer not null,
    purchase_token_hash char(64) not null,
    processing_state varchar(24) not null check (processing_state in (
        'PROCESSING', 'PROCESSED', 'RETRYABLE_FAILED', 'REJECTED')),
    result_code varchar(64),
    received_at timestamptz not null default now(),
    processed_at timestamptz,
    check (char_length(trim(message_id)) > 0),
    check (char_length(trim(package_name)) > 0),
    check (purchase_token_hash ~ '^[0-9a-f]{64}$'),
    check (notification_type between 1 and 22),
    check ((processing_state = 'PROCESSING' and processed_at is null)
        or (processing_state <> 'PROCESSING' and processed_at is not null))
);

create index google_play_rtdn_token_received_idx
    on google_play_rtdn_events(purchase_token_hash, received_at desc);

create table level_reward_versions (
    id uuid primary key,
    catalog_version integer not null,
    track_code varchar(16) not null
        check (track_code in ('FREE', 'PREMIUM', 'ROYAL')),
    required_level integer not null,
    reward_asset_type varchar(20) not null
        check (reward_asset_type in ('CURRENCY', 'ITEM')),
    reward_asset_code varchar(80) not null,
    reward_amount bigint not null,
    valid_from timestamptz not null,
    valid_until timestamptz,
    active boolean not null default false,
    created_at timestamptz not null default now(),
    unique (catalog_version, track_code, required_level),
    check (catalog_version > 0),
    check (required_level between 1 and 50),
    check (char_length(trim(reward_asset_code)) > 0),
    check (reward_amount > 0),
    check (valid_until is null or valid_until > valid_from)
);

create unique index level_reward_one_active_idx
    on level_reward_versions(track_code, required_level)
    where active;

create table player_level_reward_claims (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    request_id uuid not null unique,
    request_hash char(64) not null,
    track_code varchar(16) not null
        check (track_code in ('FREE', 'PREMIUM', 'ROYAL')),
    required_level integer not null,
    reward_version_id uuid not null
        references level_reward_versions(id) on delete restrict,
    reward_asset_type varchar(20) not null
        check (reward_asset_type in ('CURRENCY', 'ITEM')),
    reward_asset_code varchar(80) not null,
    reward_amount bigint not null,
    ledger_id uuid not null unique
        references economy_ledger(id) on delete restrict,
    response_payload jsonb not null,
    claimed_at timestamptz not null,
    created_at timestamptz not null default now(),
    unique (account_id, track_code, required_level),
    check (request_hash ~ '^[0-9a-f]{64}$'),
    check (required_level between 1 and 50),
    check (char_length(trim(reward_asset_code)) > 0),
    check (reward_amount > 0)
);

create index player_level_reward_claim_account_idx
    on player_level_reward_claims(account_id, claimed_at desc);

create table player_subscription_initial_rewards (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    plan_id uuid not null
        references subscription_plans(id) on delete restrict,
    benefit_version_id uuid not null,
    reward_asset_code varchar(80) not null,
    reward_amount bigint not null,
    ledger_id uuid not null unique
        references economy_ledger(id) on delete restrict,
    granted_at timestamptz not null,
    created_at timestamptz not null default now(),
    unique (account_id, plan_id),
    constraint subscription_initial_benefit_owner_fk
        foreign key (benefit_version_id, plan_id)
        references subscription_benefit_versions(id, plan_id)
        on delete restrict,
    check (reward_asset_code = 'DIAMOND'),
    check (reward_amount > 0)
);

create table player_subscription_daily_rewards (
    id uuid primary key,
    account_id uuid not null
        references player_accounts(id) on delete restrict,
    plan_id uuid not null
        references subscription_plans(id) on delete restrict,
    reward_date date not null,
    request_id uuid not null unique,
    request_hash char(64) not null,
    benefit_version_id uuid not null,
    reward_asset_code varchar(80) not null,
    reward_amount bigint not null,
    ledger_id uuid not null unique
        references economy_ledger(id) on delete restrict,
    response_payload jsonb not null,
    granted_at timestamptz not null,
    created_at timestamptz not null default now(),
    unique (account_id, plan_id, reward_date),
    constraint subscription_daily_benefit_owner_fk
        foreign key (benefit_version_id, plan_id)
        references subscription_benefit_versions(id, plan_id)
        on delete restrict,
    check (request_hash ~ '^[0-9a-f]{64}$'),
    check (reward_asset_code = 'DIAMOND'),
    check (reward_amount > 0)
);

create index player_subscription_daily_account_date_idx
    on player_subscription_daily_rewards(account_id, reward_date desc);

comment on table subscription_plans is
    '서로 포함 관계가 없는 NYAON 자동 갱신 월정액 플랜';
comment on table player_subscriptions is
    'Google subscriptionsv2가 권한을 가진 계정별 현재 구독 상태';
comment on table player_level_reward_claims is
    '결제 주기와 재구독으로 초기화되지 않는 계정별 평생 1회 레벨 보상';
comment on table google_play_rtdn_events is
    'Pub/Sub messageId 기반 Google Play 구독 상태 알림 멱등 기록';
