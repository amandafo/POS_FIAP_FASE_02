CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    
    -- key_hash armazena o hash SHA-256 da chave, que tem 64 caracteres hexadecimais
    key_hash VARCHAR(64) NOT NULL UNIQUE, 
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO api_keys (name, key_hash)
VALUES ('dev-service-key', '2e578016fea003ec4d25057d13307a6762e2ca7e4e22b93b0fcbdf67faccfb60')
ON CONFLICT (key_hash) DO NOTHING;
