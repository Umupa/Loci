//! A source's translations, beside it in the mentor's folder:
//! `translations/<language>/<id>.md`. The source itself is never touched;
//! the window decides what goes in the file (see `sourceTranslation.ts`).

use std::path::{Path, PathBuf};

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 80
        && !value.starts_with('.')
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
}

fn valid_language(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 16
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

fn translation_path(folder: &str, id: &str, language: &str) -> Result<PathBuf, String> {
    if !valid_id(id) {
        return Err(format!("Not a document id: {id}"));
    }
    if !valid_language(language) {
        return Err(format!("Not a language tag: {language}"));
    }
    let folder = crate::fs::expand_home(folder);
    if !folder.is_absolute() || !folder.is_dir() {
        return Err(format!("No mentor folder at {}", folder.display()));
    }
    Ok(folder
        .join("translations")
        .join(language)
        .join(format!("{id}.md")))
}

fn read(path: &Path) -> Result<Option<String>, String> {
    match std::fs::read_to_string(path) {
        Ok(text) => Ok(Some(text)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("{}: {error}", path.display())),
    }
}

#[tauri::command]
pub async fn source_translation_read(
    folder: String,
    id: String,
    language: String,
) -> Result<Option<String>, String> {
    let path = translation_path(&folder, &id, &language)?;
    tauri::async_runtime::spawn_blocking(move || read(&path))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn source_translation_write(
    folder: String,
    id: String,
    language: String,
    content: String,
) -> Result<(), String> {
    let path = translation_path(&folder, &id, &language)?;
    tauri::async_runtime::spawn_blocking(move || {
        let parent = path.parent().ok_or("No parent folder")?;
        std::fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
        crate::fs::write_text_file_sync(&path.to_string_lossy(), &content)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_translation_lives_beside_the_library_and_names_stay_inside_it() {
        let folder = std::env::temp_dir().join(format!("loci-translation-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let path = translation_path(&folder.to_string_lossy(), "k8s-pod", "zh-CN").unwrap();
        assert_eq!(path, folder.join("translations/zh-CN/k8s-pod.md"));
        assert!(translation_path(&folder.to_string_lossy(), "../soul", "zh-CN").is_err());
        assert!(translation_path(&folder.to_string_lossy(), "k8s", "../x").is_err());
        assert!(translation_path("/no/such/folder", "k8s", "zh-CN").is_err());
        assert_eq!(read(&path).unwrap(), None);
        std::fs::remove_dir_all(folder).unwrap();
    }
}
