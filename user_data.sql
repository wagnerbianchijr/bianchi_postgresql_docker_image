-- sql file executed when provisioning a new container
ALTER USER postgres WITH ENCRYPTED PASSWORD 'SCRAM-SHA-256$4096:joauLVTofMpXr83+IDdIlw==$ebUTFlHI6vtHCiOZd8K97D9+ZKSJQcELRQWj6HsQdhc=:dSMM0r6FiLx8kTmUSvtlyTTYJrrSlVUHQLVrc4s6YUY=';
CREATE USER repluser WITH REPLICATION ENCRYPTED PASSWORD 'SCRAM-SHA-256$4096:joauLVTofMpXr83+IDdIlw==$ebUTFlHI6vtHCiOZd8K97D9+ZKSJQcELRQWj6HsQdhc=:dSMM0r6FiLx8kTmUSvtlyTTYJrrSlVUHQLVrc4s6YUY=';