create table player_settings (
    account_id uuid primary key references player_accounts(id) on delete restrict,
    effect_sound_enabled boolean not null default true,
    background_music_enabled boolean not null default true,
    reduced_effects_enabled boolean not null default false,
    reduced_critical_effects_enabled boolean not null default false,
    damage_numbers_enabled boolean not null default true,
    joystick_visible boolean not null default true,
    language_code varchar(16) not null default 'en'
        check (language_code in (
            'ko', 'en', 'ja', 'zh-Hans', 'zh-Hant', 'th', 'vi', 'id',
            'es', 'pt', 'de', 'fr', 'ru', 'ar', 'tr')),
    revision bigint not null default 1 check (revision >= 1),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table player_share_rewards (
    account_id uuid primary key references player_accounts(id) on delete restrict,
    id uuid not null unique,
    shared boolean not null default false,
    reward_claimed boolean not null default false,
    shared_at timestamptz,
    reward_claimed_at timestamptz,
    share_target varchar(255),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (not reward_claimed or shared),
    check ((not shared and shared_at is null) or (shared and shared_at is not null)),
    check ((not reward_claimed and reward_claimed_at is null)
        or (reward_claimed and reward_claimed_at is not null))
);
