create table korion_wallet_link_requests (
    id uuid primary key,
    account_id uuid not null references player_accounts(id) on delete restrict,
    address varchar(64) not null,
    status varchar(16) not null
        check (status in ('PENDING', 'APPROVED', 'REJECTED', 'EXPIRED', 'FAILED')),
    expires_at timestamptz not null,
    failure_code varchar(64),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    completed_at timestamptz,
    unique (id, account_id),
    check (expires_at > created_at),
    check (
        (status = 'PENDING' and completed_at is null)
        or (status <> 'PENDING' and completed_at is not null)
    )
);

create unique index korion_wallet_link_requests_pending_account_idx
    on korion_wallet_link_requests (account_id)
    where status = 'PENDING';

create index korion_wallet_link_requests_account_created_idx
    on korion_wallet_link_requests (account_id, created_at desc);

create table player_korion_wallet_links (
    account_id uuid primary key references player_accounts(id) on delete restrict,
    address varchar(64) not null unique,
    verified_request_id uuid not null unique,
    verified_at timestamptz not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint player_korion_wallet_links_request_account_fk
        foreign key (verified_request_id, account_id)
        references korion_wallet_link_requests(id, account_id) on delete restrict
);

create table player_account_link_rewards (
    account_id uuid primary key references player_accounts(id) on delete restrict,
    id uuid not null unique,
    reward_claimed boolean not null default false,
    reward_claimed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (
        (not reward_claimed and reward_claimed_at is null)
        or (reward_claimed and reward_claimed_at is not null)
    )
);

comment on table korion_wallet_link_requests is
    'NYAON 계정에서 시작한 KORION 지갑 푸시 서명 연동 요청';
comment on table player_korion_wallet_links is
    'KORION이 서명 검증한 계정별 TRON 지갑 연결';
comment on table player_account_link_rewards is
    'Google 및 KORION 이중 연동 1회 보상 권한 행';
