#!/bin/bash
# =============================================================================
# Initialize Multiple Databases for Open WebUI Stack
# =============================================================================
# This script creates separate databases and users for each service
# It reads credentials from environment variables

set -e

# Function to create database and user
create_db_and_user() {
    local db_name=$1
    local db_user=$2
    local db_password=$3

    echo "Creating database '$db_name' with user '$db_user'..."

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
        -- Create user if not exists
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${db_user}') THEN
                CREATE ROLE ${db_user} WITH LOGIN PASSWORD '${db_password}';
            END IF;
        END
        \$\$;
        
        -- Create database if not exists
        SELECT 'CREATE DATABASE ${db_name} OWNER ${db_user}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec
        
        -- Grant privileges
        GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
EOSQL

    # Grant schema permissions
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db_name" <<EOSQL
        GRANT ALL ON SCHEMA public TO ${db_user};
EOSQL

    echo "Database '$db_name' created successfully."
}

# Create Open WebUI database
create_db_and_user "$OPENWEBUI_DB_NAME" "$OPENWEBUI_DB_USER" "$OPENWEBUI_DB_PASSWORD"

# Create LiteLLM database
create_db_and_user "$LITELLM_DB_NAME" "$LITELLM_DB_USER" "$LITELLM_DB_PASSWORD"

echo "All databases initialized successfully!"
