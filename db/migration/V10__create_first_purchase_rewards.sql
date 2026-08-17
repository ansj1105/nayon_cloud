alter table store_purchase_receipts
    add constraint store_purchase_receipts_id_account_key
    unique (id, account_id);

alter table player_equipment
    add constraint player_equipment_id_account_key
    unique (id, account_id);

create table first_purchase_reward_versions (
    id uuid primary key,
    version integer not null unique,
    equipment_catalog_version varchar(40) not null,
    equipment_grade varchar(20) not null,
    diamond_amount bigint not null,
    gold_amount bigint not null,
    valid_from timestamptz not null,
    valid_until timestamptz,
    active boolean not null default false,
    created_at timestamptz not null default now(),
    check (version > 0),
    check (equipment_catalog_version ~ '^[a-z0-9][a-z0-9._-]{2,39}$'),
    check (equipment_grade in ('COMMON')),
    check (diamond_amount > 0),
    check (gold_amount > 0),
    check (valid_until is null or valid_until > valid_from)
);

create unique index first_purchase_reward_versions_one_active_idx
    on first_purchase_reward_versions (active)
    where active;

create index first_purchase_reward_versions_validity_idx
    on first_purchase_reward_versions (active, valid_from, valid_until);

create table player_first_purchase_rewards (
    id uuid primary key,
    account_id uuid not null unique
        references player_accounts(id) on delete restrict,
    qualifying_receipt_id uuid not null unique,
    reward_version_id uuid not null
        references first_purchase_reward_versions(id) on delete restrict,
    equipment_id uuid not null unique,
    equipment_code varchar(80) not null,
    equipment_grade varchar(20) not null,
    diamond_amount bigint not null,
    gold_amount bigint not null,
    diamond_balance bigint not null,
    gold_balance bigint not null,
    granted_at timestamptz not null,
    created_at timestamptz not null default now(),
    constraint player_first_purchase_rewards_receipt_owner_fk
        foreign key (qualifying_receipt_id, account_id)
        references store_purchase_receipts(id, account_id) on delete restrict,
    constraint player_first_purchase_rewards_equipment_owner_fk
        foreign key (equipment_id, account_id)
        references player_equipment(id, account_id) on delete restrict,
    check (char_length(trim(equipment_code)) > 0),
    check (equipment_grade in ('COMMON')),
    check (diamond_amount > 0),
    check (gold_amount > 0),
    check (diamond_balance >= diamond_amount),
    check (gold_balance >= gold_amount)
);

create index player_first_purchase_rewards_granted_idx
    on player_first_purchase_rewards (granted_at desc);

insert into first_purchase_reward_versions(
    id, version, equipment_catalog_version, equipment_grade,
    diamond_amount, gold_amount, valid_from, active)
values ('00000000-0000-0000-0000-000000001001', 1,
        'unity-equipment-2026-08-16', 'COMMON', 50, 10000,
        '2026-08-17 00:00:00+09', true);

comment on table first_purchase_reward_versions is
    '첫 Google Play 구매에 적용되는 불변 보상 버전';
comment on table player_first_purchase_rewards is
    '계정당 한 번 자동 지급된 첫 구매 보상 스냅샷';
