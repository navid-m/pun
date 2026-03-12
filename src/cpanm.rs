//! CPAN client implementation - replacement for cpanm
//!
//! GPL-3.0 - Navid M (C) 2026

use flate2::read::GzDecoder;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::Command;
use tar::Archive;
use tempfile::TempDir;

const DEFAULT_MIRROR: &str = "https://www.cpan.org";
const PACKAGES_FILE: &str = "modules/02packages.details.txt.gz";

#[derive(Debug, Clone)]
pub struct CpanClient {
    mirror: String,
    cache_dir: PathBuf,
    local_lib: PathBuf,
}

#[derive(Debug, Clone)]
struct ModuleInfo {
    version: String,
    distribution: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct MetaSpec {
    #[serde(default)]
    prereqs: HashMap<String, HashMap<String, HashMap<String, String>>>,
}

impl CpanClient {
    pub fn new(local_lib: &Path) -> Result<Self, String> {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let cache_dir = PathBuf::from(home).join(".pun").join("cpan_cache");

        if !cache_dir.exists() {
            fs::create_dir_all(&cache_dir).map_err(|e| e.to_string())?;
        }

        Ok(CpanClient {
            mirror: DEFAULT_MIRROR.to_string(),
            cache_dir,
            local_lib: local_lib.to_path_buf(),
        })
    }

    pub fn install_module(&self, module_spec: &str) -> Result<String, String> {
        let (module_name, version_req) = self.parse_module_spec(module_spec);

        println!("Resolving {}...", module_name);

        let packages_index = self.fetch_packages_index()?;
        let module_info = self.resolve_module(&module_name, &packages_index)?;

        if let Some(ver_req) = version_req {
            if !self.version_matches(&module_info.version, &ver_req) {
                return Err(format!(
                    "Version mismatch: found {}, required {}",
                    module_info.version, ver_req
                ));
            }
        }

        println!("Found {} in {}", module_name, module_info.distribution);

        let dist_path = self.download_distribution(&module_info.distribution)?;

        let temp_dir = TempDir::new().map_err(|e| e.to_string())?;
        let extract_dir = self.extract_distribution(&dist_path, temp_dir.path())?;

        let meta = self.read_metadata(&extract_dir)?;
        self.install_dependencies(&meta, &packages_index)?;

        self.build_and_install(&extract_dir)?;

        Ok(module_info.version)
    }

    fn parse_module_spec(&self, spec: &str) -> (String, Option<String>) {
        if let Some(pos) = spec.find('@') {
            let module = spec[..pos].to_string();
            let version = spec[pos + 1..].to_string();
            (module, Some(version))
        } else {
            (spec.to_string(), None)
        }
    }

    fn fetch_packages_index(&self) -> Result<HashMap<String, ModuleInfo>, String> {
        let cache_file = self.cache_dir.join("02packages.details.txt.gz");

        if !cache_file.exists() || self.is_cache_stale(&cache_file) {
            println!("Fetching CPAN index...");
            let url = format!("{}/{}", self.mirror, PACKAGES_FILE);

            let response = reqwest::blocking::get(&url)
                .map_err(|e| format!("Failed to fetch index: {}", e))?;

            if !response.status().is_success() {
                return Err(format!("HTTP error: {}", response.status()));
            }

            let bytes = response
                .bytes()
                .map_err(|e| format!("Failed to read response: {}", e))?;

            fs::write(&cache_file, &bytes).map_err(|e| format!("Failed to cache index: {}", e))?;
        }

        self.parse_packages_index(&cache_file)
    }

    fn is_cache_stale(&self, cache_file: &Path) -> bool {
        if let Ok(metadata) = fs::metadata(cache_file) {
            if let Ok(modified) = metadata.modified() {
                if let Ok(elapsed) = modified.elapsed() {
                    return elapsed.as_secs() > 86400;
                }
            }
        }
        true
    }

    fn parse_packages_index(&self, file: &Path) -> Result<HashMap<String, ModuleInfo>, String> {
        let f = File::open(file).map_err(|e| e.to_string())?;
        let gz = GzDecoder::new(f);
        let reader = BufReader::new(gz);

        let mut modules = HashMap::new();
        let mut in_data = false;

        for line in reader.lines() {
            let line = line.map_err(|e| e.to_string())?;

            if line.is_empty() {
                in_data = true;
                continue;
            }

            if !in_data {
                continue;
            }

            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 3 {
                let module = parts[0].to_string();
                let version = parts[1].to_string();
                let distribution = parts[2].to_string();

                modules.insert(
                    module.clone(),
                    ModuleInfo {
                        version,
                        distribution,
                    },
                );
            }
        }

        Ok(modules)
    }

    fn resolve_module(
        &self,
        module_name: &str,
        index: &HashMap<String, ModuleInfo>,
    ) -> Result<ModuleInfo, String> {
        index
            .get(module_name)
            .cloned()
            .ok_or_else(|| format!("Module {} not found in CPAN index", module_name))
    }

    fn version_matches(&self, found: &str, required: &str) -> bool {
        found == required || found >= required
    }

    fn download_distribution(&self, dist_path: &str) -> Result<PathBuf, String> {
        let filename = dist_path.split('/').last().unwrap();
        let cache_file = self.cache_dir.join(filename);

        if cache_file.exists() {
            println!("Using cached {}", filename);
            return Ok(cache_file);
        }

        println!("Downloading {}...", filename);
        let url = format!("{}/authors/id/{}", self.mirror, dist_path);

        let response =
            reqwest::blocking::get(&url).map_err(|e| format!("Failed to download: {}", e))?;

        if !response.status().is_success() {
            return Err(format!("HTTP error: {}", response.status()));
        }

        let bytes = response
            .bytes()
            .map_err(|e| format!("Failed to read response: {}", e))?;

        fs::write(&cache_file, &bytes)
            .map_err(|e| format!("Failed to save distribution: {}", e))?;

        Ok(cache_file)
    }

    fn extract_distribution(&self, archive_path: &Path, dest: &Path) -> Result<PathBuf, String> {
        println!("Extracting...");

        let file = File::open(archive_path).map_err(|e| e.to_string())?;
        let gz = GzDecoder::new(file);
        let mut archive = Archive::new(gz);

        archive.unpack(dest).map_err(|e| e.to_string())?;

        let entries = fs::read_dir(dest).map_err(|e| e.to_string())?;
        for entry in entries {
            let entry = entry.map_err(|e| e.to_string())?;
            if entry.file_type().map_err(|e| e.to_string())?.is_dir() {
                return Ok(entry.path());
            }
        }

        Err("No directory found in archive".to_string())
    }

    fn read_metadata(&self, dist_dir: &Path) -> Result<MetaSpec, String> {
        let meta_json = dist_dir.join("META.json");
        let meta_yml = dist_dir.join("META.yml");

        if meta_json.exists() {
            let content = fs::read_to_string(&meta_json).map_err(|e| e.to_string())?;
            serde_json::from_str(&content).map_err(|e| format!("Failed to parse META.json: {}", e))
        } else if meta_yml.exists() {
            Ok(MetaSpec {
                prereqs: HashMap::new(),
            })
        } else {
            Ok(MetaSpec {
                prereqs: HashMap::new(),
            })
        }
    }

    fn install_dependencies(
        &self,
        meta: &MetaSpec,
        _index: &HashMap<String, ModuleInfo>,
    ) -> Result<(), String> {
        let mut to_install = HashSet::new();

        if let Some(runtime) = meta.prereqs.get("runtime") {
            if let Some(requires) = runtime.get("requires") {
                for (module, _version) in requires {
                    if !self.is_core_module(module) && !self.is_installed(module) {
                        to_install.insert(module.clone());
                    }
                }
            }
        }

        if let Some(build) = meta.prereqs.get("build") {
            if let Some(requires) = build.get("requires") {
                for (module, _version) in requires {
                    if !self.is_core_module(module) && !self.is_installed(module) {
                        to_install.insert(module.clone());
                    }
                }
            }
        }

        for module in to_install {
            println!("Installing dependency: {}", module);
            if let Err(e) = self.install_module(&module) {
                eprintln!("Warning: Failed to install {}: {}", module, e);
            }
        }

        Ok(())
    }

    fn is_core_module(&self, module: &str) -> bool {
        matches!(
            module,
            "strict"
                | "warnings"
                | "Carp"
                | "Exporter"
                | "File::Spec"
                | "File::Path"
                | "File::Basename"
                | "Data::Dumper"
                | "Scalar::Util"
                | "List::Util"
                | "Storable"
                | "POSIX"
                | "Fcntl"
                | "IO::File"
                | "IO::Handle"
        )
    }

    fn is_installed(&self, module: &str) -> bool {
        let lib_path = self.local_lib.join("lib").join("perl5");
        if !lib_path.exists() {
            return false;
        }

        let module_path = module.replace("::", "/");
        let pm_file = lib_path.join(format!("{}.pm", module_path));
        pm_file.exists()
    }

    fn build_and_install(&self, dist_dir: &Path) -> Result<(), String> {
        let makefile_pl = dist_dir.join("Makefile.PL");
        let build_pl = dist_dir.join("Build.PL");

        if makefile_pl.exists() {
            self.build_with_makemaker(dist_dir)?;
        } else if build_pl.exists() {
            self.build_with_module_build(dist_dir)?;
        } else {
            return Err("No Makefile.PL or Build.PL found".to_string());
        }

        Ok(())
    }

    fn build_with_makemaker(&self, dist_dir: &Path) -> Result<(), String> {
        println!("Configuring with Makefile.PL...");

        let lib_path = self.local_lib.join("lib").join("perl5");
        let arch_path = lib_path.join("auto");

        fs::create_dir_all(&lib_path).map_err(|e| e.to_string())?;
        fs::create_dir_all(&arch_path).map_err(|e| e.to_string())?;

        let status = Command::new("perl")
            .arg("Makefile.PL")
            .arg(format!("INSTALL_BASE={}", self.local_lib.display()))
            .current_dir(dist_dir)
            .env("PERL5LIB", lib_path.to_string_lossy().to_string())
            .status()
            .map_err(|e| format!("Failed to run Makefile.PL: {}", e))?;

        if !status.success() {
            return Err("Makefile.PL failed".to_string());
        }

        println!("Building...");
        let status = Command::new("make")
            .current_dir(dist_dir)
            .status()
            .map_err(|e| format!("Failed to run make: {}", e))?;

        if !status.success() {
            return Err("make failed".to_string());
        }

        println!("Installing...");
        let status = Command::new("make")
            .arg("install")
            .current_dir(dist_dir)
            .status()
            .map_err(|e| format!("Failed to run make install: {}", e))?;

        if !status.success() {
            return Err("make install failed".to_string());
        }

        Ok(())
    }

    fn build_with_module_build(&self, dist_dir: &Path) -> Result<(), String> {
        println!("Configuring with Build.PL...");

        let lib_path = self.local_lib.join("lib").join("perl5");
        fs::create_dir_all(&lib_path).map_err(|e| e.to_string())?;

        let status = Command::new("perl")
            .arg("Build.PL")
            .arg(format!("--install_base={}", self.local_lib.display()))
            .current_dir(dist_dir)
            .env("PERL5LIB", lib_path.to_string_lossy().to_string())
            .status()
            .map_err(|e| format!("Failed to run Build.PL: {}", e))?;

        if !status.success() {
            return Err("Build.PL failed".to_string());
        }

        println!("Building...");
        let status = Command::new("./Build")
            .current_dir(dist_dir)
            .status()
            .map_err(|e| format!("Failed to run Build: {}", e))?;

        if !status.success() {
            return Err("Build failed".to_string());
        }

        println!("Installing...");
        let status = Command::new("./Build")
            .arg("install")
            .current_dir(dist_dir)
            .status()
            .map_err(|e| format!("Failed to run Build install: {}", e))?;

        if !status.success() {
            return Err("Build install failed".to_string());
        }

        Ok(())
    }
}

pub fn install_module(module_spec: &str, local_lib: &Path) -> Result<String, String> {
    let client = CpanClient::new(local_lib)?;
    client.install_module(module_spec)
}
