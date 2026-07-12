-- Folder icons were stored only in iOS UserDefaults (FolderIconStore), so they
-- were lost on reinstall and invisible to the web app. Persist the chosen
-- SF Symbol name per folder; NULL means "default icon" (folder.fill).
ALTER TABLE folders ADD COLUMN IF NOT EXISTS icon TEXT;
