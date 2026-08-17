drop table if exists player_first_purchase_rewards;
drop table if exists first_purchase_reward_versions;
alter table if exists player_equipment
    drop constraint if exists player_equipment_id_account_key;
alter table if exists store_purchase_receipts
    drop constraint if exists store_purchase_receipts_id_account_key;
