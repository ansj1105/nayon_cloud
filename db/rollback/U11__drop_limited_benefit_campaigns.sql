drop table if exists player_limited_benefit_claims;
drop table if exists admob_reward_callbacks;
drop table if exists limited_benefit_ad_sessions;
drop table if exists limited_benefit_offer_rewards;
drop table if exists limited_benefit_offers;
drop table if exists limited_benefit_campaign_versions;

delete from store_offers
 where offer_code in ('limited_paid_3000_a', 'limited_paid_7000_a',
                      'limited_paid_14000_a', 'limited_paid_14000_b');

alter table store_purchase_receipts
    drop constraint if exists store_purchase_receipts_state_payload_check;
alter table store_purchase_receipts
    add constraint store_purchase_receipts_check check (
        (state = 'PENDING_VERIFICATION'
            and product_version_id is null and granted_at is null)
        or (state = 'REJECTED'
            and rejection_code is not null and granted_at is null)
        or (state = 'GRANTED'
            and product_id is not null and product_version_id is not null
            and verified_at is not null and reward_asset_code is not null
            and reward_amount > 0 and total_asset_balance >= 0
            and granted_at is not null)
    );
alter table store_purchase_receipts drop column fulfillment_type;
alter table store_product_versions drop column fulfillment_type;
