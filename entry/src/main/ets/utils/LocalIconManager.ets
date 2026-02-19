import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { JSON as ArkJSON } from '@kit.ArkTS'; // Use ArkTS JSON util if needed, or standard JSON

export interface AppData {
  c: string; // category
  l: string; // local filename (required for local mode)
  u?: string; // remote url (deprecated)
  isCustom?: boolean; // is imported custom icon
  filename?: string; // fallback compatibility
}

export interface AppInfo {
  name: string;
  icon: string; // URL or file:// URI
  category: string;
  isCustom?: boolean;
}

interface SearchResult {
  key: string;
  data: AppData;
}

export class LocalIconManager {
  private static instance: LocalIconManager;
  private appDataMap: Record<string, AppData> = {};
  private isLoaded: boolean = false;
  private initPromise: Promise<void> | null = null;
  private context: Context | null = null;
  private cacheDir: string = '';
  private customIconDir: string = '';
  private customConfigPath: string = '';

  private constructor() {}

  public static getInstance(): LocalIconManager {
    if (!LocalIconManager.instance) {
      LocalIconManager.instance = new LocalIconManager();
    }
    return LocalIconManager.instance;
  }

  private ensureDir(path: string) {
    try {
      fs.mkdirSync(path);
    } catch (e) {
      // Ignore if file exists (code 13900015)
      // Also check message content as fallback if code is generic? 13900015 is standard in HarmonyOS for fs.
      if (e.code !== 13900015) {
        console.warn(`ensureDir warning for ${path}: ${JSON.stringify(e)}`);
      }
    }
  }

  private exists(path: string): boolean {
    try {
      // accessSync is unreliable on some devices/paths (returns false negative)
      // statSync is more robust for checking existence
      const stat = fs.statSync(path);
      return !!stat;
    } catch (e) {
      return false;
    }
  }

  public async init(context: Context): Promise<void> {
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = new Promise(async (resolve) => {
      try {
        this.context = context;
        this.cacheDir = context.filesDir + '/icons';
        this.customIconDir = context.filesDir + '/imported_icons';
        this.customConfigPath = this.customIconDir + '/icon_index.json';

        this.ensureDir(this.cacheDir);
        this.ensureDir(this.customIconDir);

        const resourceManager = context.resourceManager;

        // Try to load built-in icons
        try {
          const fileData = await resourceManager.getRawFileContent('app_data.json');
          const textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
          const jsonString = textDecoder.decodeWithStream(fileData);
          this.appDataMap = JSON.parse(jsonString) as Record<string, AppData>;
        } catch (e) {
          console.error('LocalIconManager: Failed to load built-in app_data.json', JSON.stringify(e));
        }

        // Load custom icons
        await this.loadCustomIcons();

        this.isLoaded = true;
        console.info('LocalIconManager loaded successfully, total apps:', Object.keys(this.appDataMap).length);
        resolve();
      } catch (e) {
        console.error('LocalIconManager init failed:', JSON.stringify(e));
        this.initPromise = null; // 重置 promise 以允许重试
        resolve();
      }
    });

    return this.initPromise;
  }

  private async loadCustomIcons() {
    try {
      let configPath = this.customConfigPath;

      // If not at root, search one level deep
      if (!this.exists(configPath)) {
        if (this.exists(this.customIconDir)) {
          const files = fs.listFileSync(this.customIconDir);
          for (const f of files) {
            const subPath = `${this.customIconDir}/${f}`;
            try {
              if (fs.statSync(subPath).isDirectory()) {
                const potentialConfig = `${subPath}/icon_index.json`;
                if (this.exists(potentialConfig)) {
                  configPath = potentialConfig;
                  console.error(`Found icon_index.json in subdir: ${configPath}`);
                  break;
                }
              }
            } catch (statErr) {
              // Ignore
            }
          }
        }
      }

      if (this.exists(configPath)) {
        const content = fs.readTextSync(configPath);
        if (content) {
          // Define standard object type for parsing
          const rawData = JSON.parse(content) as Record<string, object>;

          let icons: Record<string, object> = {};

          if (rawData['icons']) {
            icons = rawData['icons'] as Record<string, object>;
          } else {
            icons = rawData;
          }

          let count = 0;
          Object.keys(icons).forEach(key => {
            const item = icons[key] as Record<string, string>; // Assume values are simple objects with string props
            // Support both 'filename' (external/legacy) and 'l' (internal/new fallback)
            const fname = item.filename || item.l;
            if (item && fname) {
              this.appDataMap[key] = {
                c: item.category || (item.c as string) || '自定义',
                l: fname,
                isCustom: true
              };
              count++;
            }
          });
          console.error(`Loaded ${count} custom icons from ${configPath}`);
        }
      } else {
        console.warn(`icon_index.json not found in ${this.customIconDir} (checked root and 1 level deep)`);
      }
    } catch (e) {
      console.error(`Failed to load custom icons: ${JSON.stringify(e)}`);
    }
  }

  // Helper to copy file
  private copyFile(src: string, dest: string) {
    try {
      const input = fs.openSync(src, fs.OpenMode.READ_ONLY);
      const output = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(input.fd, output.fd);
      fs.closeSync(input);
      fs.closeSync(output);
    } catch (e) {
      console.error(`Failed to copy ${src} to ${dest}: ${e}`);
    }
  }

  // Recursive copy of directory contents
  private copyDirRecursive(src: string, dest: string) {
    if (!this.exists(src)) return;
    this.ensureDir(dest);
    const files = fs.listFileSync(src);
    for (const f of files) {
      const srcPath = `${src}/${f}`;
      const destPath = `${dest}/${f}`;
      const stat = fs.statSync(srcPath);
      if (stat.isDirectory()) {
        this.copyDirRecursive(srcPath, destPath);
      } else {
        this.copyFile(srcPath, destPath);
      }
    }
  }

  // Recursive delete
  private rmdirRecursive(path: string) {
    if (!this.exists(path)) return;
    try {
      const files = fs.listFileSync(path);
      for (const f of files) {
        const curPath = `${path}/${f}`;
        if (fs.statSync(curPath).isDirectory()) {
          this.rmdirRecursive(curPath);
        } else {
          fs.unlinkSync(curPath);
        }
      }
      fs.rmdirSync(path);
    } catch (e) {
      console.error(`Failed to delete ${path}: ${e}`);
    }
  }

  public async importIconPackage(srcUri: string, onProgress?: (progress: number) => void): Promise<number> {
    console.error(`[Import] Starting import from ${srcUri}`);
    onProgress?.(0);
    if (!this.context) {
      console.error('[Import] Context is null');
      return 0;
    }

    const tempUnzipDir = this.context.filesDir + `/temp_unzip_${new Date().getTime()}`;
    const tempZipPath = this.context.filesDir + '/temp_icon_pack.zip';
    console.error(`[Import] Temp zip path: ${tempZipPath}`);
    console.error(`[Import] Temp unzip dir: ${tempUnzipDir}`);

    try {
      // 1. Copy ZIP to temp file
      console.error('[Import] Step 1: Opening source file...');
      const srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      console.error(`[Import] Step 1: Source fd: ${srcFile.fd}, copying to temp...`);

      // Use safe copy loop
      const destFile = fs.openSync(tempZipPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const bufSize = 64 * 1024; // Use larger buffer for better performance
      let buf = new ArrayBuffer(bufSize);
      let readLen = 0;
      let totalWritten = 0;

      // Try to estimate progress for copy (step 1: 0-20%)
      let srcSize = 0;
      try { srcSize = fs.statSync(srcFile.fd).size; } catch(e) {}

      while ((readLen = fs.readSync(srcFile.fd, buf, { length: bufSize })) > 0) {
        fs.writeSync(destFile.fd, buf, { length: readLen });
        totalWritten += readLen;
        if (srcSize > 0) {
          onProgress?.(Math.min(20, Math.floor((totalWritten / srcSize) * 20)));
        }
      }
      fs.fsyncSync(destFile.fd);
      fs.closeSync(srcFile);
      fs.closeSync(destFile);
      console.info(`[Import] Step 1: Copied ${totalWritten} bytes.`);
      onProgress?.(20);

      // Verify file presence by listing directory
      try {
        const dirFiles = fs.listFileSync(this.context.filesDir);
        console.error(`[Import] filesDir listing: ${JSON.stringify(dirFiles)}`);
        const stat = fs.statSync(tempZipPath);
        console.error(`[Import] Temp zip stat: size=${stat.size}, mode=${stat.mode}`);
      } catch (statErr) {
        console.error(`[Import] Verification failed: ${JSON.stringify(statErr)}`);
      }

      // 2. Unzip to unique temp dir (avoids collision)
      console.error('[Import] Step 2: Creating temp dir...');
      this.ensureDir(tempUnzipDir);
      console.error('[Import] Step 2: Decompressing...');
      // Ensure zip file actually exists
      if (!this.exists(tempZipPath)) {
        // Don't throw, just warn - maybe access is strict but stat worked?
        console.error(`[Import] WARNING: 'exists' check failed for ${tempZipPath}. Attempting zlib anyway.`);
      }
      await zlib.decompressFile(tempZipPath, tempUnzipDir);
      console.error('[Import] Step 2: Decompression complete.');
      onProgress?.(40);

      // 3. Find icon_index.json root
      console.error('[Import] Step 3: Searching for config...');
      let contentRoot = tempUnzipDir;
      let configPath = `${tempUnzipDir}/icon_index.json`;
      let newData: Record<string, object> = {};

      // DEBUG: List unzip results
      try {
        const files = fs.listFileSync(tempUnzipDir);
        console.error(`[Import] Unzipped items (${files.length}): ${JSON.stringify(files.slice(0, 10))}...`);
      } catch (listErr) {
        console.error(`[Import] Failed to list unzip dir: ${JSON.stringify(listErr)}`);
      }

      if (!this.exists(configPath)) {
        console.error('[Import] Config not at root, checking subdirs...');
        try {
          // Search one level deep
          const files = fs.listFileSync(tempUnzipDir);
          for (const f of files) {
            const subPath = `${tempUnzipDir}/${f}`;
            try {
              if (fs.statSync(subPath).isDirectory()) {
                const subConfig = `${subPath}/icon_index.json`;
                // Use explicit stat instead of exists helper for clarity
                try {
                  if (fs.accessSync(subConfig) === undefined) {
                    contentRoot = subPath;
                    configPath = subConfig;
                    console.error(`[Import] Found content root at subdir: ${contentRoot}`);
                    break;
                  }
                } catch (accessErr) {
                  // File not found, continue
                }
              }
            } catch (statErr) {
              console.error(`[Import] Stat failed for ${subPath}: ${JSON.stringify(statErr)}`);
            }
          }
        } catch (dirErr) {
          console.error(`[Import] Subdir search failed: ${JSON.stringify(dirErr)}`);
        }
      }

      // Helper to count files for progress
      const countFiles = (dir: string): number => {
        let count = 0;
        try {
          const items = fs.listFileSync(dir);
          for (const item of items) {
            const itemPath = `${dir}/${item}`;
            if (fs.statSync(itemPath).isDirectory()) {
              count += countFiles(itemPath);
            } else {
              count++;
            }
          }
        } catch (e) {}
        return count;
      }

      if (!this.exists(configPath)) {
        console.error(`[Import] icon_index.json not found. Creating fallback config from matching images...`);

        // Fallback: Scan for images that match known app data
        const newIcons: Record<string, object> = {};

        // calculate total files for progress (40-100%)
        const totalFiles = countFiles(tempUnzipDir);
        let processedFiles = 0;

        // 1. Build map of needed filenames from appDataMap (excluding already valid ones? No, just match all)
        // filename -> keys[]
        const neededFiles = new Map<string, string[]>();
        const keys = Object.keys(this.appDataMap);
        for (const key of keys) {
          const data = this.appDataMap[key] as AppData;
          if (data && data.l) {
            const fname = data.l;
            if (!neededFiles.has(fname)) {
              neededFiles.set(fname, []);
            }
            neededFiles.get(fname)?.push(key);
          }
        }

        // 2. Scan unzip dir for matches
        let foundCount = 0;
        // Recursive scanner to find images deeper in folders if needed, or just root/subroot from previous step
        // We already have 'files' from root listed above
        // Let's iterate all files in tempUnzipDir recursively
        const scanAndImport = async (dir: string) => {
          try {
            const items = fs.listFileSync(dir);
            for (const item of items) {
              const itemPath = `${dir}/${item}`;
              // Safe stat
              let isDir = false;
              try { isDir = fs.statSync(itemPath).isDirectory(); } catch (e) { continue; }

              if (isDir) {
                await scanAndImport(itemPath);
              } else {
                processedFiles++;
                // Report progress (40-100)
                if (totalFiles > 0) {
                  const p = 40 + Math.floor((processedFiles / totalFiles) * 60);
                  onProgress?.(p);
                }

                // Yield every 20 files to keep UI responsive
                if (processedFiles % 20 === 0) {
                  await new Promise<void>(resolve => setTimeout(resolve, 0));
                }

                // Check if it is an image
                const lowerItem = item.toLowerCase();
                if (lowerItem.endsWith('.png') || lowerItem.endsWith('.jpg') || lowerItem.endsWith('.jpeg') || lowerItem.endsWith('.webp')) {

                  // 1. Copy file to customIconDir (Always)
                  const destPath = `${this.customIconDir}/${item}`;
                  this.copyFile(itemPath, destPath);

                  // 2. Check overlap with neededFiles (Link to existing App)
                  if (neededFiles.has(item)) {
                    const targetKeys = neededFiles.get(item);
                    if (targetKeys) {
                      for (const k of targetKeys) {
                        const originalData = this.appDataMap[k] as AppData;
                        newIcons[k] = {
                          c: originalData.c,
                          l: item,
                          filename: item,
                          isCustom: true
                        } as AppData;
                      }
                    }
                  }

                  // 3. Register as a standalone custom icon (So it appears in library even if not matched)
                  // Use filename without extension as the key
                  let keyName = item;
                  const lastDot = item.lastIndexOf('.');
                  if (lastDot > 0) {
                    keyName = item.substring(0, lastDot);
                  }

                  if (!newIcons[keyName]) {
                    newIcons[keyName] = {
                      c: '自定义', // Default category
                      l: item,
                      filename: item,
                      isCustom: true
                    } as AppData;
                  }

                  foundCount++;
                }
              }
            }
          } catch (e) {
            console.error(`[Import] Scan failed for ${dir}: ${e}`);
          }
        };

        await scanAndImport(tempUnzipDir);
        console.error(`[Import] Fallback complete. Found and matched ${foundCount} icons.`);

        // Prepare newData for merging
        newData['icons'] = newIcons;

        // Bypass the normal "Move/Copy" step 5 since we did it inline
        // But step 4 merge logic still needs 'newData'
      } else {
        // Normal path: Config found
        console.error(`[Import] Step 3: Config found at ${configPath}`);
        const newContent = fs.readTextSync(configPath);
        newData = JSON.parse(newContent) as Record<string, object>;

        // Normal copy step (Step 5) will run later using contentRoot
      }

      // 4. Merge Configuration
      console.error('[Import] Step 4: Merging config...');
      let newIcons: Record<string, object> = {};
      if (newData['icons']) {
        newIcons = newData['icons'] as Record<string, object>;
      } else {
        newIcons = newData;
      }

      // Read existing config (if any)
      let existingIcons: Record<string, object> = {};
      if (this.exists(this.customConfigPath)) {
        try {
          const oldContent = fs.readTextSync(this.customConfigPath);
          const oldData = JSON.parse(oldContent) as Record<string, object>;
          if (oldData['icons']) {
            existingIcons = oldData['icons'] as Record<string, object>;
          } else {
            existingIcons = oldData;
          }
        } catch (e) {
          console.warn("Failed to parse existing config, starting fresh for custom icons.");
        }
      }

      // Merge (new overwrites old if key conflict)
      const mergedIcons: Record<string, object> = {};
      const existingKeys = Object.keys(existingIcons);
      for (let i = 0; i < existingKeys.length; i++) {
        mergedIcons[existingKeys[i]] = existingIcons[existingKeys[i]];
      }
      const newKeys = Object.keys(newIcons);
      for (let i = 0; i < newKeys.length; i++) {
        mergedIcons[newKeys[i]] = newIcons[newKeys[i]];
      }

      const mergedConfig: Record<string, object> = { "icons": mergedIcons };

      // Write merged config to customIconDir
      this.ensureDir(this.customIconDir);
      const configFile = fs.openSync(this.customConfigPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(configFile.fd, JSON.stringify(mergedConfig));
      fs.fsyncSync(configFile.fd); // Flush
      fs.closeSync(configFile);
      console.error('[Import] Step 4: Config merged and saved.');

      // 5. Move/Copy files based on contentRoot (Only if we found a config, fallback did copy inline)
      if (contentRoot && configPath !== 'fallback') {
        console.error('[Import] Step 5: Copying assets from contentRoot (Flattening)...');

        // Helper to flatten copy
        const flattenCopy = (src: string) => {
          if (!this.exists(src)) return;
          const items = fs.listFileSync(src);
          for (const item of items) {
            const itemPath = `${src}/${item}`;
            // Skip config file
            if (item === 'icon_index.json') continue;

            try {
              if (fs.statSync(itemPath).isDirectory()) {
                // Recurse into subdirectories
                flattenCopy(itemPath);
              } else {
                // Is file -> Copy to ROOT of customIconDir
                // This handles "icons/Douyin.png" -> "imported_icons/Douyin.png"
                const destPath = `${this.customIconDir}/${item}`;
                this.copyFile(itemPath, destPath);
              }
            } catch (e) {
              console.error(`[Import] Flatten copy failed for ${item}: ${e}`);
            }
          }
        };

        try {
          flattenCopy(contentRoot);
          console.error('[Import] Step 5: Assets copied (Flattened).');
        } catch (e) {
          console.error(`[Import] Step 5 failed: ${e}`);
        }
      }

      // 6. Reload
      console.error('[Import] Step 6: Reloading...');
      await this.loadCustomIcons();

      // Cleanup
      console.error('[Import] Cleanup...');
      try { fs.unlinkSync(tempZipPath); } catch (e) {}
      this.rmdirRecursive(tempUnzipDir);

      // Count custom icons safely
      const count = Object.values(this.appDataMap).filter((d: AppData) => d.isCustom === true).length;
      console.error(`[Import] Success! Total custom icons: ${count}`);
      return count;
    } catch (e) {
      // Detailed error logging
      const err = e as Error;
      console.error(`[Import] FAILED: ${err.message}, Name: ${err.name}, Stack: ${err.stack}`);

      // Safe access to 'code' property
      const code = (e as Record<string, Object>)['code'];
      if (code) { console.error(`[Import] Error Code: ${code}`); }

      // Attempt cleanup
      try { fs.unlinkSync(tempZipPath); } catch (e2) {}
      this.rmdirRecursive(tempUnzipDir);

      throw new Error(`Import failed: ${err.message || JSON.stringify(e)}`);
    }
  }

  /**
   * Add a single custom icon.
   * @param srcUri Source URI (from picker)
   * @param name User-defined app name
   * @param category User-defined category
   * @returns boolean success
   */
  public async saveSingleCustomIcon(srcUri: string, name: string, category: string): Promise<boolean> {
    if (!this.context || !srcUri || !name) return false;

    try {
      this.ensureDir(this.customIconDir);

      // 1. Determine local filename (use timestamp + original extension)
      let ext = '.png';
      const lastDot = srcUri.lastIndexOf('.');
      if (lastDot > 0) {
        ext = srcUri.substring(lastDot);
        // Basic sanitization
        if (ext.length > 5) ext = '.png';
      }
      const filename = `${new Date().getTime()}${ext}`;
      const destPath = `${this.customIconDir}/${filename}`;

      // 2. Copy file
      const srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      const destFile = fs.openSync(destPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);

      const bufSize = 4096;
      let buf = new ArrayBuffer(bufSize);
      let readLen = 0;
      while ((readLen = fs.readSync(srcFile.fd, buf, { length: bufSize })) > 0) {
        fs.writeSync(destFile.fd, buf, { length: readLen });
      }
      fs.fsyncSync(destFile.fd);
      fs.closeSync(srcFile);
      fs.closeSync(destFile);

      // 3. Update Config
      let existingIcons: Record<string, object> = {};
      if (this.exists(this.customConfigPath)) {
        try {
          const oldContent = fs.readTextSync(this.customConfigPath);
          const oldData = JSON.parse(oldContent) as Record<string, object>;
          if (oldData['icons']) {
            existingIcons = oldData['icons'] as Record<string, object>;
          } else {
            existingIcons = oldData;
          }
        } catch (e) {
          console.warn("Failed to parse existing config, creating new.");
        }
      }

      const newIcon: AppData = {
        c: category || '自定义',
        l: filename,
        isCustom: true
      };
      existingIcons[name] = newIcon;

      const mergedConfig: Record<string, object> = { "icons": existingIcons };
      const configFile = fs.openSync(this.customConfigPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(configFile.fd, JSON.stringify(mergedConfig));
      fs.fsyncSync(configFile.fd);
      fs.closeSync(configFile);

      // 4. Update in-memory map
      this.appDataMap[name] = newIcon;

      console.info(`Successfully added single custom icon: ${name} (${category})`);
      return true;
    } catch (e) {
      console.error(`Failed to add single custom icon: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // Debug helper to inspect directory structure
  private listDirRecursive(path: string, depth: number = 0) {
    if (depth > 2) return; // Limit depth
    try {
      if (this.exists(path)) {
        const files = fs.listFileSync(path);
        console.info(`[DEBUG] Listing ${path} (${files.length} items):`);
        files.forEach(f => {
          console.info(`[DEBUG] ${'  '.repeat(depth)}- ${f}`);
          const fullPath = `${path}/${f}`;
          if (fs.statSync(fullPath).isDirectory()) {
            this.listDirRecursive(fullPath, depth + 1);
          }
        });
      }
    } catch (e) {
      console.error(`[DEBUG] Failed to list ${path}: ${e}`);
    }
  }

  private async resolveIconPath(data: AppData): Promise<string> {
    if (this.context) {
      let dir = this.cacheDir;

      // Check if custom - use property directly
      if (data.isCustom) {
        dir = this.customIconDir;
      }

      const filename = data.l;
      const targetPath = `${dir}/${filename}`;
      const targetUri = `file://${targetPath}`;

      if (this.exists(targetPath)) {
        return targetUri;
      }

      // Extract only if NOT custom (built-in rawfile)
      if (!data.isCustom) {
        try {
          // ... existing extraction ...
          const resourceManager = this.context.resourceManager;
          const content = await resourceManager.getRawFileContent(`icons/${filename}`);
          const file = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
          fs.writeSync(file.fd, content.buffer);
          fs.closeSync(file);
          return targetUri;
        } catch (e) {
          console.error(`Failed to extract icon ${filename}:`, JSON.stringify(e));
          return ''; // No remote fallback
        }
      } else {
        // Custom icon missing
        console.warn(`[DEBUG] Custom icon missing: Expected at ${targetPath}`);
        // ... (existing subdirectory search uses fs.listFileSync which assumes parent exists, use safe checks there too) ...
        try {
          if (this.exists(this.customIconDir)) { // Check customIconDir exists first
            const files = fs.listFileSync(this.customIconDir);
            for (const f of files) {
              const subPath = `${this.customIconDir}/${f}`;
              if (fs.statSync(subPath).isDirectory()) {
                const potentialPath = `${subPath}/${filename}`;
                if (this.exists(potentialPath)) {
                  console.info(`[DEBUG] Found icon in subdirectory: ${potentialPath}`);
                  return `file://${potentialPath}`;
                }
              }
            }
          }
        } catch (e) {}
      }
    }
    return ''; // No remote fallback
  }

  private async initWait(): Promise<void> {
    if (!this.isLoaded && this.initPromise) {
      await this.initPromise;
    }
  }

  public async getAppInfo(appName: string): Promise<AppInfo | null> {
    await this.initWait();
    if (!this.isLoaded || !appName) {
      return null;
    }
    const result = this.searchInternal(appName);
    return result ? {
      name: result.key,
      icon: await this.resolveIconPath(result.data),
      category: result.data.c,
      isCustom: result.data.isCustom
    } : null;
  }

  /* 同步搜索，但在获取Icon时可能需要异步IO */
  public async searchApp(keyword: string): Promise<AppInfo | null> {
    return this.getAppInfo(keyword);
  }

  // 新增：搜索多个应用建议
  public async searchApps(keyword: string, limit: number = 20): Promise<AppInfo[]> {
    if (!this.isLoaded || !keyword) {
      return [];
    }

    const results: AppInfo[] = [];
    const lowerKeyword = keyword.toLowerCase();
    const keys = Object.keys(this.appDataMap);

    // 简单匹配：包含关键词
    const matches = keys.filter(k => k.toLowerCase().includes(lowerKeyword));

    // 排序：优先精确匹配，然后是前缀匹配，最后是长度短的
    matches.sort((a, b) => {
      const la = a.toLowerCase();
      const lb = b.toLowerCase();
      if (la === lowerKeyword) return -1;
      if (lb === lowerKeyword) return 1;
      if (la.startsWith(lowerKeyword) && !lb.startsWith(lowerKeyword)) return -1;
      if (!la.startsWith(lowerKeyword) && lb.startsWith(lowerKeyword)) return 1;
      return a.length - b.length;
    });

    const topMatches = matches.slice(0, limit);
    for (const key of topMatches) {
      const info = await this.getAppInfo(key);
      if (info) {
        results.push(info);
      }
    }
    return results;
  }


  private searchInternal(keyword: string): SearchResult | null {
    let bestMatch: SearchResult | null = null;
    let shortestKeyLength = Infinity;
    const lowerKeyword = keyword.toLowerCase();

    const keys = Object.keys(this.appDataMap);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const lowerKey = key.toLowerCase();
      if (lowerKey.includes(lowerKeyword) || lowerKeyword.includes(lowerKey)) {
        if (key.length < shortestKeyLength) {
          shortestKeyLength = key.length;
          bestMatch = { key: key, data: this.appDataMap[key] };
        }
      }
    }
    return bestMatch;
  }

  public async getAllApps(): Promise<AppInfo[]> {
    await this.initWait();
    if (!this.isLoaded) return [];

    const results: AppInfo[] = [];
    const keys = Object.keys(this.appDataMap);

    // Process in chunks/parallel if needed, but for now linear await is safer for file I/O stability
    for (const key of keys) {
      const data = this.appDataMap[key];
      // Ensure icon exists (extract if needed)
      const uri = await this.resolveIconPath(data);
      if (uri) {
        results.push({
          name: key,
          icon: uri,
          category: data.c,
          isCustom: data.isCustom
        });
      }
    }
    return results;
  }

  public async getAllCategories(): Promise<string[]> {
    await this.initWait();
    if (!this.isLoaded) return [];
    const categories = new Set<string>();
    Object.values(this.appDataMap).forEach(d => categories.add(d.c));
    return Array.from(categories).sort();
  }

  /**
   * Batch delete custom icons.
   * @param names Array of app names to delete
   * @returns number of successfully deleted icons
   */
  public async deleteCustomIcons(names: string[]): Promise<number> {
    if (!this.context || !names || names.length === 0) return 0;

    let deleteCount = 0;
    try {
      // 1. Load current custom config
      let existingIcons: Record<string, AppData> = {};
      if (this.exists(this.customConfigPath)) {
        try {
          const content = fs.readTextSync(this.customConfigPath);
          const data = JSON.parse(content) as Record<string, object>;
          if (data['icons']) {
            existingIcons = data['icons'] as Record<string, AppData>;
          } else {
            existingIcons = data as Record<string, AppData>;
          }
        } catch (e) {
          console.error('Failed to parse custom config for deletion');
          return 0;
        }
      }

      // 2. Iterate and check for deletion
      let updatedIcons: Record<string, AppData> = {};
      let updatedAppData: Record<string, AppData> = {};
      let hasChange = false;

      const currentKeys = Object.keys(existingIcons);
      for (const k of currentKeys) {
        if (names.includes(k) && existingIcons[k].isCustom) {
          // Mark for deletion: skip adding to updated maps and delete file
          const data = existingIcons[k];
          const filePath = `${this.customIconDir}/${data.l}`;
          try {
            if (this.exists(filePath)) {
              fs.unlinkSync(filePath);
            }
          } catch (e) {
            console.warn(`Failed to delete icon file: ${filePath}`);
          }
          deleteCount++;
          hasChange = true;
        } else {
          // Keep this icon
          updatedIcons[k] = existingIcons[k];
        }
      }

      if (hasChange) {
        // Update memory map similarly to avoid 'delete'
        const memoryKeys = Object.keys(this.appDataMap);
        for (const k of memoryKeys) {
          if (!(names.includes(k) && this.appDataMap[k].isCustom)) {
            updatedAppData[k] = this.appDataMap[k];
          }
        }
        this.appDataMap = updatedAppData;
        existingIcons = updatedIcons;
      }

      // 3. Save updated config
      if (deleteCount > 0) {
        const updatedConfig: Record<string, object> = { "icons": existingIcons };
        const configFile = fs.openSync(this.customConfigPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(configFile.fd, JSON.stringify(updatedConfig));
        fs.fsyncSync(configFile.fd);
        fs.closeSync(configFile);
        console.info(`Successfully deleted ${deleteCount} custom icons.`);
      }

      return deleteCount;
    } catch (e) {
      console.error(`Failed to delete custom icons: ${JSON.stringify(e)}`);
      return 0;
    }
  }

  /**
   * Register a custom icon from Base64 string.
   * Useful for restoring from backup or sync.
   * @param base64 Base64 string
   * @param name App name
   * @param category Category
   * @param overwrite Whether to overwrite existing
   * @returns boolean success
   */
  public async registerBase64Icon(base64: string, name: string, category: string, overwrite: boolean = true): Promise<boolean> {
    if (!this.context || !base64 || !name) return false;

    try {
      this.ensureDir(this.customIconDir);

      let dataToSave = base64;
      if (base64.startsWith('data:')) {
        dataToSave = base64.substring(base64.indexOf(',') + 1);
      }

      // 1. Check if exists
      if (!overwrite && this.appDataMap[name]) {
        return true; // Already exists
      }

      // 2. Determine filename
      let ext = '.png';
      if (base64.includes('image/jpeg')) ext = '.jpg';
      else if (base64.includes('image/webp')) ext = '.webp';

      const filename = `${new util.TextEncoder().encodeInto(name).reduce((a, b) => a + b, 0)}_${Date.now()}${ext}`;
      const destPath = `${this.customIconDir}/${filename}`;

      // 3. Save file
      const helper = new util.Base64Helper();
      const buffer = helper.decodeSync(dataToSave).buffer;
      const file = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buffer);
      fs.fsyncSync(file.fd);
      fs.closeSync(file);

      // 4. Update Config
      let existingIcons: Record<string, object> = {};
      if (this.exists(this.customConfigPath)) {
        try {
          const oldContent = fs.readTextSync(this.customConfigPath);
          const oldData = JSON.parse(oldContent) as Record<string, object>;
          existingIcons = (oldData['icons'] || oldData) as Record<string, object>;
        } catch (e) {}
      }

      const newIcon: AppData = {
        c: category || '自定义',
        l: filename,
        isCustom: true
      };
      existingIcons[name] = newIcon;

      const mergedConfig: Record<string, object> = { "icons": existingIcons };
      const configFile = fs.openSync(this.customConfigPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(configFile.fd, JSON.stringify(mergedConfig));
      fs.fsyncSync(configFile.fd);
      fs.closeSync(configFile);

      // 5. Update Memory
      this.appDataMap[name] = newIcon;

      return true;
    } catch (e) {
      console.error(`Failed to register base64 icon for ${name}: ${JSON.stringify(e)}`);
      return false;
    }
  }
}
