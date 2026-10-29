package general.backend;

import haxe.Json;

typedef ModsList =
{
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

class Mods
{
	static public var currentModDirectory:String = '';
	public static var ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'stageScripts',
		'achievements'
	];

	private static var globalMods:Array<String> = [];

	inline public static function getGlobalMods()
		return globalMods;

	inline public static function pushGlobalMods() // prob a better way to do this but idc
	{
		globalMods = [];
		for (mod in parseList().enabled)
		{
			var pack:Dynamic = getPack(mod);
			if (pack != null && pack.runsGlobally)
				globalMods.push(mod);
		}
		return globalMods;
	}

	inline public static function getModDirectories():Array<String>
	{
		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		if (FileSystem.exists(modsFolder))
		{
			for (folder in FileSystem.readDirectory(modsFolder))
			{
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder) && !list.contains(folder))
					list.push(folder);
			}
		}
		#end
		return list;
	}

	inline public static function mergeAllTextsNamed(path:String, defaultDirectory:String = null, allowDuplicates:Bool = false)
	{
		if (defaultDirectory == null)
			defaultDirectory = Paths.getSharedPath();
		defaultDirectory = defaultDirectory.trim();
		if (!defaultDirectory.endsWith('/'))
			defaultDirectory += '/';
		if (!defaultDirectory.startsWith('assets/'))
			defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if (paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
		{
			var list:Array<String> = CoolUtil.coolTextFile(file);
			for (value in list)
				if ((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);
		}
		return mergedList;
	}

	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true)
	{
		var foldersToCheck:Array<String> = [];
		#if sys
		if (FileSystem.exists(path + fileToFind))
		#end
		foldersToCheck.push(path + fileToFind);

		#if MODS_ALLOWED
		if (mods)
		{
			// Global mods first
			for (mod in Mods.getGlobalMods())
			{
				var folder:String = Paths.mods(mod + '/' + fileToFind);
				if (FileSystem.exists(folder) && !foldersToCheck.contains(folder))
					foldersToCheck.push(folder);
			}

			// Then "PsychEngine/mods/" main folder
			var folder:String = Paths.mods(fileToFind);
			if (FileSystem.exists(folder) && !foldersToCheck.contains(folder))
				foldersToCheck.push(Paths.mods(fileToFind));

			// And lastly, the loaded mod's folder
			if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var folder:String = Paths.mods(Mods.currentModDirectory + '/' + fileToFind);
				if (FileSystem.exists(folder) && !foldersToCheck.contains(folder))
					foldersToCheck.push(folder);
			}
		}
		#end
		return foldersToCheck;
	}

	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED
		if (folder == null)
			folder = Mods.currentModDirectory;

		var path = Paths.mods(folder + '/pack.json');
		if (FileSystem.exists(path))
		{
			try
			{
				#if sys
				var rawJson:String = File.getContent(path);
				#else
				var rawJson:String = Assets.getText(path);
				#end
				if (rawJson != null && rawJson.length > 0)
					return tjson.TJSON.parse(rawJson);
			}
			catch (e:Dynamic)
			{
				trace(e);
			}
		}
		#end
		return null;
	}

	public static var updatedOnState:Bool = false;


	// ── 大肥鱼引擎 · 安全模式（启动看门狗升级版）────────────────────────
	// 旧做法：上次启动没走完 → 把 modsList.txt 里所有模组改成 |0（永久禁用！）
	//   → 在加载页被系统杀 / 内存不足 / 删标记失败，都会被误判成崩溃，
	//     于是每次启动都把模组全禁掉（「不管崩没崩都禁模组」）。
	// 新做法：崩溃后只在【本次启动】临时跳过模组，一行都不写 modsList.txt；
	//   走到标题画面就算启动成功 → 删标记 → 下次启动自动恢复。
	public static var bfSafeMode:Bool = false;
	public static var bfSafeModeReason:String = "";

	public static function bfConsumeSafeMode():Void
	{
		bfSafeMode = false;
		bfSafeModeReason = "";
		try
		{
			var f:String = ".bf_safe_mode";
			if (sys.FileSystem.exists(f))
			{
				bfSafeMode = true;
				try
				{
					bfSafeModeReason = sys.io.File.getContent(f);
				}
				catch (e:Dynamic) {}
				sys.FileSystem.deleteFile(f); // 只生效这一次
				trace("[BF] 安全模式：本次启动不加载模组（" + bfSafeModeReason + "）");
			}
		}
		catch (e:Dynamic) trace("[BF] safe mode error: " + e);
	}
	inline public static function parseList():ModsList
	{
		if (!updatedOnState)
			updateModList();
		var list:ModsList = {enabled: [], disabled: [], all: []};

		#if MODS_ALLOWED
		try
		{
			for (mod in CoolUtil.coolTextFile('modsList.txt'))
			{
				// trace('Mod: $mod');
				if (mod.trim().length < 1)
					continue;

				var dat = mod.split("|");
				list.all.push(dat[0]);
				if (dat[1] == "1")
				{
					if (bfSafeMode) list.disabled.push(dat[0]);
					else list.enabled.push(dat[0]);
				}
				else
					list.disabled.push(dat[0]);
			}
		}
		catch (e)
		{
			trace(e);
		}
		#end
		return list;
	}

	private static function updateModList()
	{
		#if MODS_ALLOWED
		// Find all that are already ordered
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String> = [];
		try
		{
			for (mod in CoolUtil.coolTextFile('modsList.txt'))
			{
				var dat:Array<String> = mod.split("|");
				var folder:String = dat[0];
				if (folder.trim().length > 0
					&& FileSystem.exists(Paths.mods(folder))
					&& FileSystem.isDirectory(Paths.mods(folder))
					&& !added.contains(folder))
				{
					added.push(folder);
					list.push([folder, (dat[1] == "1")]);
				}
			}
		}
		catch (e)
		{
			trace(e);
		}

		// Scan for folders that aren't on modsList.txt yet
		for (folder in getModDirectories())
		{
			if (folder.trim().length > 0
				&& FileSystem.exists(Paths.mods(folder))
				&& FileSystem.isDirectory(Paths.mods(folder))
				&& !ignoreModFolders.contains(folder)
				&& !added.contains(folder))
			{
				added.push(folder);
				list.push([folder, true]); // i like it false by default. -bb //Well, i like it True! -Shadow Mario (2022)
				// Shadow Mario (2023): What the fuck was bb thinking
			}
		}

		// Now save file
		var fileStr:String = '';
		for (values in list)
		{
			if (fileStr.length > 0)
				fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

		File.saveContent('modsList.txt', fileStr);
		updatedOnState = true;
		// trace('Saved modsList.txt');
		#end
	}

	// Very NB
	public static function toDisplayPath(path:String, ?ignores:Array<String>):String {
		var ar = ~/^(.*\/)?(mods|assets)\//;
		if(ar.match(path)) {
			switch(ar.matched(2)) {
				case "mods":
					var r = ~/^(.*\/)?mods\/([^\/]+)\/(.*)$/g;
					if(r.match(path)) {
						if(ignores == null) ignores = Mods.ignoreModFolders;
						if(ignores.contains(r.matched(2))) {
							return r.replace(path, "(Mod:[*Global])$2/$3");
						}
					}
					return r.replace(path, "(Mod:'$2')$3");
				case "assets":
					var r = ~/^(.*\/)?assets\/(.*)$/g;
					return r.replace(path, "(Assets)$2");
			}
		}
		return path;
	}

	public static function loadTopMod()
	{
		Mods.currentModDirectory = '';

		#if MODS_ALLOWED
		var list:Array<String> = Mods.parseList().enabled;
		if (list != null && list[0] != null)
			Mods.currentModDirectory = list[0];
		#end
	}
}
