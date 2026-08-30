-- Link only the regenerated mixed-language pronunciation files uploaded to
-- the public local-food-audio bucket. The explicit ID-to-object mapping keeps
-- this data repair deterministic and avoids name-based matching.
with audio_files(local_food_id, object_name) as (
  values
    (16, '16_sup_gearbox_mixed_v4.mp3'),
    (28, '28_hainanese_chicken_rice_mixed_v4.mp3'),
    (30, '30_dry_bak_kut_teh_mixed_v4.mp3'),
    (35, '35_curry_laksa_mixed_v4.mp3'),
    (36, '36_claypot_chicken_rice_mixed_v4.mp3'),
    (41, '41_fish_head_noodle_soup_mixed_v4.mp3'),
    (42, '42_kaya_toast_mixed_v4.mp3'),
    (48, '48_banana_leaf_rice_mixed_v4.mp3'),
    (52, '52_mutton_biryani_mixed_v4.mp3'),
    (69, '69_bambangan_pickle_mixed_v4.mp3'),
    (73, '73_roti_cobra_mixed_v4.mp3'),
    (82, '82_terung_dayak_soup_mixed_v4.mp3'),
    (85, '85_musang_king_durian_mixed_v4.mp3'),
    (100, '100_kacang_ma_chicken_mixed_v4.mp3'),
    (106, '106_roti_cheese_mixed_v4.mp3'),
    (121, '121_ufo_tart_mixed_v4.mp3'),
    (122, '122_yam_rice_mixed_v4.mp3'),
    (123, '123_ipoh_bean_sprout_chicken_mixed_v4.mp3'),
    (124, '124_chicken_rice_ball_mixed_v4.mp3'),
    (125, '125_oyster_omelette_mixed_v4.mp3'),
    (132, '132_marmite_chicken_mixed_v4.mp3'),
    (140, '140_ipoh_white_coffee_mixed_v4.mp3'),
    (141, '141_chilli_pan_mee_mixed_v4.mp3'),
    (146, '146_economy_rice_mixed_v4.mp3'),
    (147, '147_pork_ball_noodle_soup_mixed_v4.mp3'),
    (148, '148_fried_bee_hoon_mixed_v4.mp3'),
    (149, '149_kung_po_chicken_mixed_v4.mp3'),
    (150, '150_butter_prawn_mixed_v4.mp3'),
    (151, '151_salted_egg_prawn_mixed_v4.mp3'),
    (152, '152_curry_fish_head_mixed_v4.mp3'),
    (153, '153_yam_ring_mixed_v4.mp3'),
    (154, '154_claypot_tofu_mixed_v4.mp3'),
    (156, '156_half_boiled_eggs_mixed_v4.mp3'),
    (157, '157_soya_bean_milk_mixed_v4.mp3'),
    (159, '159_tenom_coffee_mixed_v4.mp3'),
    (163, '163_green_bean_soup_mixed_v4.mp3'),
    (165, '165_cheng_tng_mixed_v4.mp3'),
    (166, '166_grass_jelly_mixed_v4.mp3'),
    (172, '172_salt_baked_chicken_mixed_v4.mp3'),
    (173, '173_ipoh_caramel_custard_mixed_v4.mp3'),
    (177, '177_gula_apong_ice_cream_mixed_v4.mp3'),
    (178, '178_teh_c_peng_special_mixed_v4.mp3'),
    (180, '180_sago_worms_mixed_v4.mp3'),
    (193, '193_white_lady_kuching_mixed_v4.mp3'),
    (349, '349_jiu_hu_char_mixed_v4.mp3'),
    (351, '351_assam_prawn_mixed_v4.mp3'),
    (356, '356_nyonya_fish_maw_soup_mixed_v4.mp3'),
    (357, '357_assam_pedas_pomfret_mixed_v4.mp3'),
    (358, '358_salted_fish_bone_curry_mixed_v4.mp3'),
    (372, '372_ramly_burger_mixed_v4.mp3')
)
update public.local_food as food
set audio_guide_url =
  'https://odtmtukexckfjbuqkxyo.supabase.co/storage/v1/object/public/' ||
  'local-food-audio/' || audio_files.object_name
from audio_files
where food.local_food_id = audio_files.local_food_id;
