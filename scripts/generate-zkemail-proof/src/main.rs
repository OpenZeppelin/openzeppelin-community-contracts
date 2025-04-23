use std::fs::{self, create_dir_all};
use std::path::Path;
use std::str::FromStr;

use anyhow::{Context, Result};
use ethers::types::{H256, U256};
use relayer_utils::ParsedEmail;
use serde_json::json;
use slog::{info, o, Logger};
use uuid::Uuid;

use email_tx_builder::{
    abis::EmailAuthMsg,
    command::get_encoded_command_params,
    dkim::check_and_update_dkim,
    model::{RequestModel, RequestStatus, EmailTxAuth},
    prove::generate_email_proof,
    RelayerState,
    chain::ChainClient,
};

// Create a simple logger for output
fn setup_logger() -> Logger {
    slog::Logger::root(slog::Discard, o!())
}

// Generate a sample email with a signHash command
fn generate_sample_email(hash: &str, domain: &str, account_salt: &str) -> String {
    format!(
        "From: test@{}\r\n\
         To: relayer@example.com\r\n\
         Subject: signHash {}\r\n\
         Message-ID: <test123@{}>\r\n\
         Date: Thu, 21 Mar 2024 12:00:00 +0000\r\n\
         DKIM-Signature: v=1; a=rsa-sha256; d={}; s=selector; h=from:to:subject; bh=base64==; b=signature==\r\n\
         \r\n\
         This is a test email to sign hash {}.\r\n",
        domain, hash, domain, domain, hash
    )
}

// Mock a request model for the proof generation
fn create_mock_request(template_id: &str, account_salt: &str) -> RequestModel {
    RequestModel {
        id: Uuid::new_v4(),
        subject: "signHash".to_string(),
        email_tx_auth: EmailTxAuth {
            template_id: U256::from_str(template_id).unwrap(),
            account_salt: Some(H256::from_str(account_salt).unwrap()),
            chain: Some("sepolia".to_string()),
            dkim_contract_address: Some(H256::zero().to_string()),
        },
        status: RequestStatus::Received,
        from_email: Some("test@example.com".to_string()),
        reply_to_message_id: None,
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
    }
}

// Setup a mock RelayerState for proof generation
fn create_mock_relayer_state() -> RelayerState {
    let logger = setup_logger();
    
    // Create a minimal configuration
    let config = email_tx_builder::config::Config {
        modal_token_id: None,
        modal_token_secret: None,
        domain: "example.com".to_string(),
        // Add other required fields with default values
        db_url: "sqlite::memory:".to_string(),
        path: email_tx_builder::config::PathConfig {
            email_templates: "./templates".to_string(),
        },
        smtp_url: "http://localhost:3000".to_string(),
        imap_url: "http://localhost:3001".to_string(),
        chains: vec![],
        prover_url: "http://localhost:3002".to_string(),
    };
    
    RelayerState {
        config,
        db: sled::Config::new().temporary(true).open().unwrap(),
        http_client: reqwest::Client::new(),
        logger,
    }
}

// Main function to generate and save the proof
async fn generate_proof(
    hash: &str, 
    domain: &str,
    account_salt: &str, 
    template_id: &str,
    output_path: &str
) -> Result<()> {
    let email = generate_sample_email(hash, domain, account_salt);
    let request = create_mock_request(template_id, account_salt);
    let relayer_state = create_mock_relayer_state();
    
    // Parse the email
    let parsed_email = ParsedEmail::new_from_raw_email(&email)
        .await
        .context("Failed to parse email")?;
    
    info!(relayer_state.logger, "Parsed email: {:?}", parsed_email);
    
    // Generate command params
    let command_params_encoded = get_encoded_command_params(&email, request.clone())
        .await
        .context("Failed to get encoded command params")?;
    
    // Generate the email proof
    let email_proof = generate_email_proof(&email, request.clone(), relayer_state.clone())
        .await
        .context("Failed to generate email proof")?;
    
    // Create the EmailAuthMsg
    let email_auth_msg = EmailAuthMsg {
        template_id: request.email_tx_auth.template_id,
        command_params: command_params_encoded,
        skipped_command_prefix: U256::zero(),
        proof: email_proof,
    };
    
    // Convert to JSON
    let json_output = json!({
        "emailAuthMsg": email_auth_msg,
        "hash": hash,
        "domain": domain,
        "accountSalt": account_salt,
        "templateId": template_id,
    });
    
    // Ensure output directory exists
    let output_dir = Path::new(output_path).parent().unwrap_or(Path::new("."));
    create_dir_all(output_dir).context("Failed to create output directory")?;
    
    // Write to file
    fs::write(output_path, serde_json::to_string_pretty(&json_output)?)
        .context("Failed to write proof to file")?;
    
    println!("Successfully generated and saved proof to {}", output_path);
    Ok(())
}

// Entry point for the script
#[tokio::main]
async fn main() -> Result<()> {
    // Example values
    let hash = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    let domain = "example.com";
    let account_salt = "0x046582bce36cdd0a8953b9d40b8f20d58302bacf3bcecffeb6741c98a52725e2";
    let template_id = "0x0000000000000000000000000000000000000000000000000000000000000001";
    let output_path = "../test/fixtures/zkemail/valid-proof.json";
    
    generate_proof(hash, domain, account_salt, template_id, output_path).await?;
    
    Ok(())
}
