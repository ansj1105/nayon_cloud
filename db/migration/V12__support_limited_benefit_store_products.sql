alter table store_product_versions
    drop constraint store_product_versions_reward_asset_type_check;
alter table store_product_versions
    drop constraint store_product_versions_reward_asset_code_check;
alter table store_product_versions
    drop constraint store_product_versions_reward_amount_check;

alter table store_product_versions alter column reward_asset_type drop not null;
alter table store_product_versions alter column reward_asset_code drop not null;
alter table store_product_versions alter column reward_amount drop not null;

alter table store_product_versions
    add constraint store_product_versions_fulfillment_payload_check check (
        (fulfillment_type = 'DIRECT_CURRENCY'
            and reward_asset_type is not null
            and reward_asset_type = 'CURRENCY'
            and reward_asset_code is not null
            and reward_asset_code ~ '^[A-Z][A-Z0-9_]{1,39}$'
            and reward_amount is not null
            and reward_amount > 0)
        or (fulfillment_type = 'LIMITED_BENEFIT'
            and reward_asset_type is null
            and reward_asset_code is null
            and reward_amount is null)
    );

comment on column store_product_versions.fulfillment_type is
    'DIRECT_CURRENCY는 영수증 검증 즉시 지급, LIMITED_BENEFIT은 일일 혜택 claim의 증빙으로만 사용';
