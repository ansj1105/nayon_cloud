create table weekly_gift_reward_versions (
    id uuid primary key,
    version integer not null unique,
    reward_asset_type varchar(30) not null,
    reward_asset_code varchar(80) not null,
    reward_amount bigint not null check (reward_amount > 0),
    valid_from timestamptz not null,
    valid_until timestamptz,
    active boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (valid_until is null or valid_until > valid_from)
);

create unique index weekly_gift_reward_versions_active_uk
    on weekly_gift_reward_versions(active) where active;

create table player_weekly_gift_weeks (
    account_id uuid not null references player_accounts(id) on delete cascade,
    week_start date not null,
    claimed_at timestamptz,
    claim_request_id uuid unique,
    reward_version_id uuid references weekly_gift_reward_versions(id),
    claim_response jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (account_id, week_start),
    check (extract(isodow from week_start) = 1),
    check (
        (claimed_at is null and claim_request_id is null
            and reward_version_id is null and claim_response is null)
        or
        (claimed_at is not null and claim_request_id is not null
            and reward_version_id is not null and claim_response is not null)
    )
);

create table player_weekly_gift_login_days (
    account_id uuid not null,
    week_start date not null,
    login_date date not null,
    first_seen_at timestamptz not null default now(),
    primary key (account_id, week_start, login_date),
    foreign key (account_id, week_start)
        references player_weekly_gift_weeks(account_id, week_start)
        on delete cascade,
    check (login_date >= week_start and login_date < week_start + 7)
);

create index player_weekly_gift_login_days_week_idx
    on player_weekly_gift_login_days(account_id, week_start, first_seen_at);
