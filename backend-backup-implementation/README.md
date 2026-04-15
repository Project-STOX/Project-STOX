# Supabase Local Backup & Audit System

This project provides an automated, offline backup solution for a Supabase database. It uses a **Grandfather-Father-Son (GFS)** protocol to maintain both short-term emergency recovery files and long-term auditing archives.

## Features
- **High-Frequency DR**: Backs up every 4 hours with 3-day/8-week/90-day retention policies.
- **SME Long-Term Audit**: Backs up daily at midnight with 14-day/25-month/3-year/7-year retention policies.
- **Auto-Verification**: Every backup is automatically restored to a local "mirror" database to ensure the data is valid and one-click recoverable.
- **Human-Readable Logs**: Live history logs maintained for non-technical staff oversight.

## Setup Instructions

1. **Install Docker**: Ensure Docker Desktop is installed and running on your computer.
2. **Environment Configuration**:
   - Duplicate the `.env.example` file and rename the copy to `.env`.
   - Open `.env` and enter your Supabase connection string and a secret password for your local database.
3. **Start the System**:
   - Open a terminal or command prompt in this folder.
   - Run the following command:
     ```bash
      docker-compose up -d --build
     ```

## How to Check Status
- **Logs**: Open `full_backup/backup_history.log` or `ind_backup/backup_history.log` to see a text history of all backups.
- **Live Feed**: Run `docker-compose logs -f` in your terminal to see the system working in real-time.
- **Files**: Your backup `.sql` files will appear automatically in the `full_backup/` and `ind_backup/` folders.

- ## Limitations and future roadmap
- **Compression**: Implement a properly compressed file backup instead of .sql
- **NO 3-2-1**: Implement automatic redundent backup of 3 copies, 2 different media, 1 offsite after the initial backup_database succeeds
- **NO Incident Detection capabilities**: Implement an Incident Detection system and rules to notice in case of pg_dump failiure. 
