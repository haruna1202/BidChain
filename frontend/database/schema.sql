CREATE DATABASE IF NOT EXISTS pokevault
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE pokevault;

CREATE TABLE IF NOT EXISTS cards (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  chain_card_id BIGINT UNSIGNED NOT NULL,
  profile_id BIGINT UNSIGNED NOT NULL,
  seller_address CHAR(42) NOT NULL,
  name VARCHAR(160) NOT NULL,
  set_name VARCHAR(200) NOT NULL DEFAULT '',
  issuer VARCHAR(100) NOT NULL,
  grade VARCHAR(40) NOT NULL,
  certificate_number VARCHAR(120) NOT NULL,
  certificate_key CHAR(66) NOT NULL,
  metadata_hash CHAR(66) NOT NULL,
  profile_json LONGTEXT NOT NULL,
  front_image_url VARCHAR(255) NOT NULL,
  back_image_url VARCHAR(255) NOT NULL,
  certificate_file_url VARCHAR(255) NOT NULL,
  transaction_hash CHAR(66) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cards_chain_card_id (chain_card_id),
  UNIQUE KEY uq_cards_profile_id (profile_id),
  KEY idx_cards_seller (seller_address),
  KEY idx_cards_certificate (certificate_number)
) ENGINE=InnoDB;
