alter table store_product_versions
    add column fulfillment_type varchar(24) not null default 'DIRECT_CURRENCY'
        check (fulfillment_type in ('DIRECT_CURRENCY', 'LIMITED_BENEFIT'));

alter table store_purchase_receipts
    add column fulfillment_type varchar(24) not null default 'DIRECT_CURRENCY'
        check (fulfillment_type in ('DIRECT_CURRENCY', 'LIMITED_BENEFIT'));

alter table store_purchase_receipts drop constraint store_purchase_receipts_check;
alter table store_purchase_receipts
    add constraint store_purchase_receipts_state_payload_check check (
        (state = 'PENDING_VERIFICATION'
            and product_version_id is null and granted_at is null)
        or (state = 'REJECTED'
            and rejection_code is not null and granted_at is null)
        or (state = 'GRANTED'
            and product_id is not null and product_version_id is not null
            and verified_at is not null and granted_at is not null
            and ((fulfillment_type = 'DIRECT_CURRENCY'
                    and reward_asset_code is not null
                    and reward_amount > 0 and total_asset_balance >= 0)
                 or (fulfillment_type = 'LIMITED_BENEFIT'
                    and reward_asset_code is null
                    and reward_amount is null
                    and total_asset_balance is null)))
    );

insert into store_offers(id, offer_code, display_order)
values
    ('00000000-0000-0000-0000-000000009201', 'limited_paid_3000_a', 2010),
    ('00000000-0000-0000-0000-000000009202', 'limited_paid_7000_a', 2020),
    ('00000000-0000-0000-0000-000000009203', 'limited_paid_14000_a', 2030),
    ('00000000-0000-0000-0000-000000009204', 'limited_paid_14000_b', 2040);

create table limited_benefit_campaign_versions (
    id uuid primary key,
    campaign_code varchar(64) not null,
    version integer not null,
    zone_id varchar(40) not null,
    valid_from timestamptz not null,
    valid_until timestamptz,
    active boolean not null default false,
    created_at timestamptz not null default now(),
    unique (campaign_code, version),
    unique (id, campaign_code),
    check (campaign_code ~ '^[a-z][a-z0-9_]{2,63}$'),
    check (version > 0),
    check (zone_id = 'Asia/Seoul'),
    check (valid_until is null or valid_until > valid_from)
);

create unique index limited_benefit_one_active_campaign_idx
    on limited_benefit_campaign_versions(campaign_code)
    where active;

create table limited_benefit_offers (
    id uuid primary key,
    campaign_version_id uuid not null
        references limited_benefit_campaign_versions(id) on delete restrict,
    offer_code varchar(64) not null,
    display_order integer not null,
    title varchar(100) not null,
    fulfillment_type varchar(24) not null
        check (fulfillment_type in ('FREE', 'GOOGLE_PLAY', 'ADMOB_SSV')),
    store_offer_id uuid references store_offers(id) on delete restrict,
    provider_key varchar(200),
    created_at timestamptz not null default now(),
    unique (campaign_version_id, offer_code),
    unique (campaign_version_id, display_order),
    unique (id, campaign_version_id),
    check (offer_code ~ '^[a-z][a-z0-9_]{2,63}$'),
    check (display_order >= 0),
    check (char_length(trim(title)) > 0),
    check ((fulfillment_type = 'GOOGLE_PLAY' and store_offer_id is not null)
        or (fulfillment_type <> 'GOOGLE_PLAY' and store_offer_id is null))
);

create table limited_benefit_offer_rewards (
    offer_id uuid not null,
    campaign_version_id uuid not null,
    reward_order smallint not null,
    reward_type varchar(24) not null
        check (reward_type in ('CURRENCY', 'ITEM', 'EQUIPMENT_BOX')),
    reward_code varchar(40) not null,
    amount bigint not null,
    primary key (offer_id, reward_order),
    constraint limited_benefit_reward_offer_owner_fk
        foreign key (offer_id, campaign_version_id)
        references limited_benefit_offers(id, campaign_version_id)
        on delete restrict,
    check (reward_order between 0 and 2),
    check (amount > 0),
    check ((reward_type = 'CURRENCY' and reward_code in ('DIAMOND', 'GOLD'))
        or (reward_type = 'ITEM'
            and reward_code in ('SILVER_KEY', 'GOLD_KEY', 'RANDOM_SCROLL'))
        or (reward_type = 'EQUIPMENT_BOX'
            and reward_code in ('ADVANCED_BOX', 'ALL_BOX')))
);

create table limited_benefit_ad_sessions (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    campaign_version_id uuid not null,
    offer_id uuid not null,
    cycle_date date not null,
    status varchar(16) not null
        check (status in ('PENDING', 'VERIFIED', 'CONSUMED', 'EXPIRED')),
    ad_unit_id varchar(200) not null,
    expires_at timestamptz not null,
    verified_at timestamptz,
    consumed_at timestamptz,
    transaction_id varchar(200) unique,
    created_at timestamptz not null default now(),
    unique (id, account_id, offer_id, cycle_date),
    constraint limited_benefit_ad_session_offer_owner_fk
        foreign key (offer_id, campaign_version_id)
        references limited_benefit_offers(id, campaign_version_id)
        on delete restrict,
    check (char_length(trim(ad_unit_id)) > 0),
    check (expires_at > created_at),
    check ((status = 'PENDING' and verified_at is null and consumed_at is null)
        or (status = 'VERIFIED' and verified_at is not null and consumed_at is null)
        or (status = 'CONSUMED' and verified_at is not null and consumed_at is not null)
        or status = 'EXPIRED')
);

create index limited_benefit_ad_sessions_account_cycle_idx
    on limited_benefit_ad_sessions(account_id, cycle_date, created_at desc);

create table admob_reward_callbacks (
    transaction_id varchar(200) primary key,
    ad_session_id uuid references limited_benefit_ad_sessions(id) on delete restrict,
    raw_query text not null,
    key_id bigint not null,
    verified boolean not null,
    failure_code varchar(64),
    received_at timestamptz not null default now(),
    check (char_length(trim(transaction_id)) > 0),
    check (char_length(raw_query) > 0),
    check ((verified and failure_code is null)
        or (not verified))
);

create table player_limited_benefit_claims (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    campaign_version_id uuid not null,
    offer_id uuid not null,
    cycle_date date not null,
    request_id uuid not null unique,
    request_hash char(64) not null,
    proof_type varchar(24) not null
        check (proof_type in ('FREE', 'GOOGLE_PLAY', 'ADMOB_SSV')),
    receipt_id uuid,
    ad_session_id uuid,
    response_payload jsonb not null,
    claimed_at timestamptz not null,
    created_at timestamptz not null default now(),
    unique (account_id, campaign_version_id, cycle_date, offer_id),
    constraint limited_benefit_claim_offer_owner_fk
        foreign key (offer_id, campaign_version_id)
        references limited_benefit_offers(id, campaign_version_id)
        on delete restrict,
    constraint limited_benefit_claim_receipt_owner_fk
        foreign key (receipt_id, account_id)
        references store_purchase_receipts(id, account_id)
        on delete restrict,
    constraint limited_benefit_claim_ad_session_owner_fk
        foreign key (ad_session_id, account_id, offer_id, cycle_date)
        references limited_benefit_ad_sessions(id, account_id, offer_id, cycle_date)
        on delete restrict,
    check (request_hash ~ '^[0-9a-f]{64}$'),
    check ((proof_type = 'FREE' and receipt_id is null and ad_session_id is null)
        or (proof_type = 'GOOGLE_PLAY' and receipt_id is not null and ad_session_id is null)
        or (proof_type = 'ADMOB_SSV' and receipt_id is null and ad_session_id is not null))
);

create unique index limited_benefit_claim_receipt_once_idx
    on player_limited_benefit_claims(receipt_id) where receipt_id is not null;
create unique index limited_benefit_claim_ad_session_once_idx
    on player_limited_benefit_claims(ad_session_id) where ad_session_id is not null;
create index limited_benefit_claim_account_cycle_idx
    on player_limited_benefit_claims(account_id, cycle_date, claimed_at);

insert into limited_benefit_campaign_versions(
    id, campaign_code, version, zone_id, valid_from, active)
values ('00000000-0000-0000-0000-000000011101',
        'daily_limited_benefit', 1, 'Asia/Seoul',
        '2026-08-17 00:00:00+09', true);

insert into limited_benefit_offers(
    id, campaign_version_id, offer_code, display_order, title,
    fulfillment_type, store_offer_id)
values
('00000000-0000-0000-0000-000000011201','00000000-0000-0000-0000-000000011101','paid_3000_a',0,'한정 보급 묶음','GOOGLE_PLAY','00000000-0000-0000-0000-000000009201'),
('00000000-0000-0000-0000-000000011202','00000000-0000-0000-0000-000000011101','free_01',1,'무료 보급 1','FREE',null),
('00000000-0000-0000-0000-000000011203','00000000-0000-0000-0000-000000011101','free_02',2,'무료 보급 2','FREE',null),
('00000000-0000-0000-0000-000000011204','00000000-0000-0000-0000-000000011101','ad_01',3,'영상 무료 보급 1','ADMOB_SSV',null),
('00000000-0000-0000-0000-000000011205','00000000-0000-0000-0000-000000011101','free_03',4,'무료 보급 3','FREE',null),
('00000000-0000-0000-0000-000000011206','00000000-0000-0000-0000-000000011101','free_04',5,'무료 보급 4','FREE',null),
('00000000-0000-0000-0000-000000011207','00000000-0000-0000-0000-000000011101','paid_7000_a',6,'정예 성장 묶음','GOOGLE_PLAY','00000000-0000-0000-0000-000000009202'),
('00000000-0000-0000-0000-000000011208','00000000-0000-0000-0000-000000011101','free_05',7,'무료 보급 5','FREE',null),
('00000000-0000-0000-0000-000000011209','00000000-0000-0000-0000-000000011101','free_06',8,'무료 보급 6','FREE',null),
('00000000-0000-0000-0000-000000011210','00000000-0000-0000-0000-000000011101','ad_02',9,'영상 무료 보급 2','ADMOB_SSV',null),
('00000000-0000-0000-0000-000000011211','00000000-0000-0000-0000-000000011101','free_07',10,'무료 보급 7','FREE',null),
('00000000-0000-0000-0000-000000011212','00000000-0000-0000-0000-000000011101','free_08',11,'무료 보급 8','FREE',null),
('00000000-0000-0000-0000-000000011213','00000000-0000-0000-0000-000000011101','paid_14000_a',12,'고급 헌터 묶음','GOOGLE_PLAY','00000000-0000-0000-0000-000000009203'),
('00000000-0000-0000-0000-000000011214','00000000-0000-0000-0000-000000011101','free_09',13,'무료 보급 9','FREE',null),
('00000000-0000-0000-0000-000000011215','00000000-0000-0000-0000-000000011101','free_10',14,'무료 보급 10','FREE',null),
('00000000-0000-0000-0000-000000011216','00000000-0000-0000-0000-000000011101','ad_03',15,'영상 무료 보급 3','ADMOB_SSV',null),
('00000000-0000-0000-0000-000000011217','00000000-0000-0000-0000-000000011101','free_11',16,'무료 보급 11','FREE',null),
('00000000-0000-0000-0000-000000011218','00000000-0000-0000-0000-000000011101','free_12',17,'무료 보급 12','FREE',null),
('00000000-0000-0000-0000-000000011219','00000000-0000-0000-0000-000000011101','paid_14000_b',18,'특별 헌터 묶음','GOOGLE_PLAY','00000000-0000-0000-0000-000000009204'),
('00000000-0000-0000-0000-000000011220','00000000-0000-0000-0000-000000011101','free_13',19,'무료 보급 13','FREE',null),
('00000000-0000-0000-0000-000000011221','00000000-0000-0000-0000-000000011101','free_14',20,'무료 보급 14','FREE',null),
('00000000-0000-0000-0000-000000011222','00000000-0000-0000-0000-000000011101','ad_04',21,'영상 무료 보급 4','ADMOB_SSV',null),
('00000000-0000-0000-0000-000000011223','00000000-0000-0000-0000-000000011101','free_15',22,'무료 보급 15','FREE',null),
('00000000-0000-0000-0000-000000011224','00000000-0000-0000-0000-000000011101','free_16',23,'무료 보급 16','FREE',null);

insert into limited_benefit_offer_rewards(
    offer_id, campaign_version_id, reward_order, reward_type, reward_code, amount)
values
('00000000-0000-0000-0000-000000011201','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',160),
('00000000-0000-0000-0000-000000011201','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',8),
('00000000-0000-0000-0000-000000011201','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',1),
('00000000-0000-0000-0000-000000011202','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',60),
('00000000-0000-0000-0000-000000011202','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',2),
('00000000-0000-0000-0000-000000011203','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',70),
('00000000-0000-0000-0000-000000011203','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',3),
('00000000-0000-0000-0000-000000011204','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',90),
('00000000-0000-0000-0000-000000011204','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',4),
('00000000-0000-0000-0000-000000011204','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',1),
('00000000-0000-0000-0000-000000011205','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',90),
('00000000-0000-0000-0000-000000011205','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',3),
('00000000-0000-0000-0000-000000011206','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',110),
('00000000-0000-0000-0000-000000011206','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',4),
('00000000-0000-0000-0000-000000011207','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',500),
('00000000-0000-0000-0000-000000011207','00000000-0000-0000-0000-000000011101',1,'EQUIPMENT_BOX','ADVANCED_BOX',1),
('00000000-0000-0000-0000-000000011207','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',2),
('00000000-0000-0000-0000-000000011208','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',130),
('00000000-0000-0000-0000-000000011208','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',4),
('00000000-0000-0000-0000-000000011209','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',150),
('00000000-0000-0000-0000-000000011209','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',5),
('00000000-0000-0000-0000-000000011210','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',220),
('00000000-0000-0000-0000-000000011210','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',8),
('00000000-0000-0000-0000-000000011210','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',1),
('00000000-0000-0000-0000-000000011211','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',170),
('00000000-0000-0000-0000-000000011211','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',5),
('00000000-0000-0000-0000-000000011212','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',190),
('00000000-0000-0000-0000-000000011212','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',6),
('00000000-0000-0000-0000-000000011213','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',1000),
('00000000-0000-0000-0000-000000011213','00000000-0000-0000-0000-000000011101',1,'EQUIPMENT_BOX','ALL_BOX',1),
('00000000-0000-0000-0000-000000011213','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',3),
('00000000-0000-0000-0000-000000011214','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',210),
('00000000-0000-0000-0000-000000011214','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',6),
('00000000-0000-0000-0000-000000011215','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',230),
('00000000-0000-0000-0000-000000011215','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',7),
('00000000-0000-0000-0000-000000011216','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',420),
('00000000-0000-0000-0000-000000011216','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',12),
('00000000-0000-0000-0000-000000011216','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',2),
('00000000-0000-0000-0000-000000011217','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',250),
('00000000-0000-0000-0000-000000011217','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',7),
('00000000-0000-0000-0000-000000011218','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',270),
('00000000-0000-0000-0000-000000011218','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',8),
('00000000-0000-0000-0000-000000011219','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',1400),
('00000000-0000-0000-0000-000000011219','00000000-0000-0000-0000-000000011101',1,'EQUIPMENT_BOX','ALL_BOX',2),
('00000000-0000-0000-0000-000000011219','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',4),
('00000000-0000-0000-0000-000000011220','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',290),
('00000000-0000-0000-0000-000000011220','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',8),
('00000000-0000-0000-0000-000000011221','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',310),
('00000000-0000-0000-0000-000000011221','00000000-0000-0000-0000-000000011101',1,'ITEM','GOLD_KEY',1),
('00000000-0000-0000-0000-000000011222','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',650),
('00000000-0000-0000-0000-000000011222','00000000-0000-0000-0000-000000011101',1,'ITEM','GOLD_KEY',2),
('00000000-0000-0000-0000-000000011222','00000000-0000-0000-0000-000000011101',2,'ITEM','RANDOM_SCROLL',3),
('00000000-0000-0000-0000-000000011223','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',330),
('00000000-0000-0000-0000-000000011223','00000000-0000-0000-0000-000000011101',1,'ITEM','SILVER_KEY',9),
('00000000-0000-0000-0000-000000011224','00000000-0000-0000-0000-000000011101',0,'CURRENCY','DIAMOND',360),
('00000000-0000-0000-0000-000000011224','00000000-0000-0000-0000-000000011101',1,'ITEM','GOLD_KEY',1);

comment on table limited_benefit_campaign_versions is
    'KST 일일 기간 한정 혜택의 불변 캠페인 버전';
comment on table player_limited_benefit_claims is
    '계정·캠페인·KST 일자·상품별 정확히 한 번 지급된 응답';
comment on table admob_reward_callbacks is
    'AdMob SSV 원문과 검증 결과 및 전역 거래 중복 방지 기록';
