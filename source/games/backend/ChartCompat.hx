package games.backend;

import haxe.Json;

import openfl.utils.Assets;

import games.backend.Section;
import games.backend.Song;

// ── 数据小结构 ─────────────────────────────────────────────

typedef BPMChange =
{
	var t:Float;
	var bpm:Float;
}

typedef CNote =
{
	var t:Float;
	var d:Int;
	var l:Float;
	var k:String;
}

typedef CEvent =
{
	var t:Float;
	var name:String;
	var v1:String;
	var v2:String;
}

/**
 * 原生谱面兼容层（大肥鱼引擎 0.9.0）
 *
 * 直接读 vslice / FNF 0.8+ / FNFC 目录格式的谱面，在内存里转成引擎的 SwagSong：
 *     data/songs/<歌>/<歌>-chart.json + <歌>-metadata.json
 *
 * 转换要点：
 *   · 音符时间保持谱面里的绝对毫秒，不量化 → 不会跑位
 *   · metadata.timeChanges → 段落 changeBPM（吸附到最近的 4 拍段边界）
 *   · notes.d 原样保留 0..7，配合 chartEngineVersion = Pe-1.0.4
 *     （0-3 = 玩家，4-7 = 对手）
 *   · FocusCamera 事件 → 段落 mustHitSection（引擎靠段落切换镜头）
 *   · PlayAnimation / ChangeCharacter 映射成 Psych 事件名，其余事件丢弃（引擎不认识）
 *   · playData.characters / stage / vocals → Song 字段
 */
class ChartCompat
{
	public static var lastFormat:String = 'none';
	public static var lastDetail:String = '';
	public static var lastPath:String = '';

	// ── 格式识别 ───────────────────────────────────────────────

	/**
	 * 判断是不是 vslice 系谱面：
	 *   notes 是对象（按难度分）        → vslice / FNF 0.8+ / FNFC
	 *   notes 是数组且元素有 t/d 无 sectionNotes → CNE 那种平铺数组
	 */
	public static function isVSliceChart(json:Dynamic):Bool
	{
		if (json == null) return false;
		var n:Dynamic = Reflect.field(json, 'notes');
		if (n == null) return false;
		if (!Std.isOfType(n, Array)) return true;
		var arr:Array<Dynamic> = cast n;
		if (arr.length == 0) return false;
		var first:Dynamic = arr[0];
		if (first == null) return false;
		if (Reflect.hasField(first, 'sectionNotes')) return false;
		return Reflect.hasField(first, 't') && Reflect.hasField(first, 'd');
	}

	/** 从“歌名 + 难度后缀”里拆难度（bloodmoon-hard → hard） */
	public static function difficultyOf(folder:String, songKey:String):String
	{
		var f:String = Paths.formatToSongPath(folder);
		var s:String = Paths.formatToSongPath(songKey);
		if (f.length > 0 && s.length > f.length && s.substr(0, f.length) == f)
		{
			var d:String = s.substr(f.length);
			if (d.length > 0 && d.charAt(0) == '-') d = d.substr(1);
			return d;
		}
		return '';
	}

	// ── 文件查找 ───────────────────────────────────────────────

	static function chartKeys(folder:String):Array<String>
	{
		return [
			'songs/$folder/$folder-chart',
			'$folder/$folder-chart',
			'songs/$folder/$folder'
		];
	}

	static function metadataKeys(folder:String):Array<String>
	{
		return [
			'songs/$folder/$folder-metadata',
			'$folder/$folder-metadata',
			'songs/$folder/metadata'
		];
	}

	static function loadText(key:String):Null<String>
	{
		var p:String = Paths.json(key);
		#if sys
		if (p != null && FileSystem.exists(p)) return File.getContent(p);
		#end
		if (p != null && Assets.exists(p)) return Assets.getText(p);
		return null;
	}

	/** 找原生谱面文件；找不到返回 null */
	public static function findChart(folder:String):ChartSource
	{
		for (k in chartKeys(folder))
		{
			var t:Null<String> = loadText(k);
			if (t != null)
			{
				lastPath = Paths.json(k);
				return {key: k, path: lastPath, text: t};
			}
		}
		return null;
	}

	/** 找 metadata（可选）；找不到返回 null */
	public static function findMetadata(folder:String):Dynamic
	{
		for (k in metadataKeys(folder))
		{
			var t:Null<String> = loadText(k);
			if (t != null)
			{
				try
				{
					return Json.parse(t);
				}
				catch (e:Dynamic)
				{
					trace('[BFChart] metadata 解析失败: ' + k);
				}
			}
		}
		return null;
	}

	// ── 转换主流程 ─────────────────────────────────────────────

	public static function convert(chartJson:Dynamic, metadata:Dynamic, difficulty:String, songId:String):SwagSong
	{
		var tc:Array<BPMChange> = readTimeChanges(metadata, chartJson);
		var bpm0:Float = tc[0].bpm;

		var segBeats:Array<Float> = [0.0];
		for (i in 1...tc.length)
		{
			var prev:BPMChange = tc[i - 1];
			var span:Float = tc[i].t - prev.t;
			if (span < 0) span = 0;
			segBeats.push(segBeats[i - 1] + span / (60000.0 / prev.bpm));
		}

		var notes:Array<CNote> = readNotes(chartJson, difficulty);
		var eventsRaw:Array<Dynamic> = readEventsRaw(chartJson);

		var lastT:Float = 0;
		if (notes.length > 0) lastT = notes[notes.length - 1].t;

		var totalBeats:Float = (lastT > 0 ? beatAt(lastT, tc, segBeats) : 0) + 8;
		var secCount:Int = Std.int(Math.ceil(totalBeats / 4));
		if (secCount < 1) secCount = 1;
		if (secCount > 60000) secCount = 60000; // 坏数据防御（≈4 小时）

		var sections:Array<SwagSection> = [];
		for (i in 0...secCount) sections.push(makeSection(bpm0));

		for (n in notes)
		{
			var si:Int = Std.int(Math.floor(beatAt(n.t, tc, segBeats) / 4));
			if (si < 0) si = 0;
			if (si >= secCount) si = secCount - 1;
			var arr:Array<Dynamic> = [n.t, n.d, n.l, n.k];
			sections[si].sectionNotes.push(arr);
		}

		// BPM 变化：吸附到最近的段边界，让 Conductor 的 step 表尽量准
		var bpmChanges:Int = 0;
		for (i in 1...tc.length)
		{
			var si:Int = Std.int(Math.round(segBeats[i] / 4));
			if (si < 0 || si >= secCount) continue;
			sections[si].changeBPM = true;
			sections[si].bpm = tc[i].bpm;
			bpmChanges++;
		}

		// 镜头：FocusCamera → mustHitSection；没事件的段看音符多少
		var camSet:Array<Bool> = [for (i in 0...secCount) false];
		var events:Array<CEvent> = [];
		for (e in eventsRaw)
		{
			if (e == null) continue;
			var name:String = strField(e, 'e');
			var t:Float = numField(e, 't', 0);
			var v:Dynamic = Reflect.field(e, 'v');

			if (name == 'FocusCamera')
			{
				var ch:Float = (v != null) ? numField(v, 'char', -1) : -1;
				if (ch == 0 || ch == 1)
				{
					var si:Int = Std.int(Math.floor(beatAt(t, tc, segBeats) / 4));
					if (si < 0) si = 0;
					if (si >= secCount) si = secCount - 1;
					sections[si].mustHitSection = (ch == 0); // 0 = 男朋友，1 = 爸爸
					camSet[si] = true;
				}
				continue;
			}

			var mapped:Null<CEvent> = mapEvent(name, t, v);
			if (mapped != null) events.push(mapped);
		}

		for (i in 0...secCount)
		{
			if (camSet[i]) continue;
			var p:Int = 0;
			var o:Int = 0;
			for (arr in sections[i].sectionNotes)
			{
				if (Std.int(arr[1]) < 4) p++;
				else o++;
			}
			if (p + o == 0)
				sections[i].mustHitSection = (i > 0) ? sections[i - 1].mustHitSection : true;
			else
				sections[i].mustHitSection = (p >= o);
		}

		var outEvents:Array<Dynamic> = groupEvents(events);

		// 元数据
		var pd:Dynamic = (metadata != null) ? Reflect.field(metadata, 'playData') : null;
		var chars:Dynamic = (pd != null) ? Reflect.field(pd, 'characters') : null;
		var player:String = (chars != null) ? strField(chars, 'player') : '';
		var opponent:String = (chars != null) ? strField(chars, 'opponent') : '';
		var girlfriend:String = (chars != null) ? strField(chars, 'girlfriend') : '';
		var stage:String = (pd != null) ? strField(pd, 'stage') : '';

		var pv:Array<String> = strArray(chars, 'playerVocals');
		var ov:Array<String> = strArray(chars, 'opponentVocals');
		if (ov.length == 0) ov = strArray(chars, 'opponent_vocals');
		if (pv.length == 0) pv = strArray(chars, 'player_vocals');

		var speed:Float = readSpeed(chartJson, difficulty);

		var out:SwagSong = cast {
			song: songId,
			bpm: bpm0,
			speed: speed,
			needsVoices: true,
			format: 'psych_v1',
			player1: (opponent != '' ? opponent : 'dad'),
			player2: (player != '' ? player : 'bf'),
			gfVersion: (girlfriend != '' ? girlfriend : 'gf'),
			stage: (stage != '' ? stage : 'stage'),
			mania: 3,
			notes: sections,
			events: outEvents,
			playerVocals: pv,
			opponentVocals: ov
		};

		lastFormat = 'vslice';
		lastDetail = 'notes=' + notes.length + ' sections=' + secCount + ' events=' + outEvents.length + ' bpmChanges=' + bpmChanges;
		trace('[BFChart] 原生谱面 ' + songId + ' 难度=' + (difficulty == '' ? '(默认)' : difficulty) + ' ' + lastDetail);

		return out;
	}

	// ── 读字段 ─────────────────────────────────────────────────

	static function readTimeChanges(metadata:Dynamic, chartJson:Dynamic):Array<BPMChange>
	{
		var list:Array<BPMChange> = [];
		if (metadata != null)
		{
			var raw:Dynamic = Reflect.field(metadata, 'timeChanges');
			if (raw != null && Std.isOfType(raw, Array))
			{
				for (o in (raw:Array<Dynamic>))
				{
					if (o == null) continue;
					var b:Float = numField(o, 'bpm', 0);
					if (b <= 0) continue;
					list.push({t: numField(o, 't', 0), bpm: b});
				}
			}
		}
		if (list.length == 0)
		{
			var cb:Float = numField(chartJson, 'bpm', 0);
			list.push({t: 0, bpm: (cb > 0 ? cb : 150)});
		}
		list.sort(function(a:BPMChange, b:BPMChange):Int
		{
			if (a.t < b.t) return -1;
			if (a.t > b.t) return 1;
			return 0;
		});
		if (list[0].t > 0) list.insert(0, {t: 0, bpm: list[0].bpm});
		return list;
	}

	static function readNotes(chartJson:Dynamic, difficulty:String):Array<CNote>
	{
		var notes:Dynamic = Reflect.field(chartJson, 'notes');
		var raw:Array<Dynamic> = null;

		if (notes != null && !Std.isOfType(notes, Array))
		{
			var diffs:Array<String> = Reflect.fields(notes);
			if (diffs == null) diffs = [];
			var want:String = (difficulty == null ? '' : difficulty.toLowerCase());
			var pick:String = '';
			if (want != '' && diffs.indexOf(want) >= 0) pick = want;
			else if (diffs.indexOf('normal') >= 0) pick = 'normal';
			else if (diffs.length > 0) pick = diffs[0];
			if (pick != '')
			{
				var arr:Dynamic = Reflect.field(notes, pick);
				if (arr != null && Std.isOfType(arr, Array)) raw = cast arr;
			}
		}
		else if (notes != null && Std.isOfType(notes, Array))
		{
			raw = cast notes;
		}

		var out:Array<CNote> = [];
		if (raw == null) return out;
		for (o in raw)
		{
			if (o == null) continue;
			var t:Float = numField(o, 't', -1);
			if (t < 0) continue;
			out.push({
				t: t,
				d: Std.int(numField(o, 'd', 0)),
				l: numField(o, 'l', 0),
				k: strField(o, 'k')
			});
		}
		out.sort(function(a:CNote, b:CNote):Int
		{
			if (a.t < b.t) return -1;
			if (a.t > b.t) return 1;
			return 0;
		});
		return out;
	}

	static function readEventsRaw(chartJson:Dynamic):Array<Dynamic>
	{
		var ev:Dynamic = Reflect.field(chartJson, 'events');
		if (ev != null && Std.isOfType(ev, Array)) return cast ev;
		return [];
	}

	static function readSpeed(chartJson:Dynamic, difficulty:String):Float
	{
		var sp:Dynamic = Reflect.field(chartJson, 'scrollSpeed');
		if (sp == null) return 2;
		if (Std.isOfType(sp, Float) || Std.isOfType(sp, Int))
		{
			var f:Float = cast sp;
			return (f > 0 ? f : 2);
		}
		if (Std.isOfType(sp, Array)) return 2;
		var d:String = (difficulty == null ? '' : difficulty.toLowerCase());
		var cand:Array<String> = [];
		if (d != '') cand.push(d);
		cand.push('normal');
		var fields:Array<String> = Reflect.fields(sp);
		if (fields != null) for (f in fields) cand.push(f);
		for (k in cand)
		{
			var v:Dynamic = Reflect.field(sp, k);
			if (v != null && (Std.isOfType(v, Float) || Std.isOfType(v, Int)))
			{
				var fv:Float = cast v;
				if (fv > 0) return fv;
			}
		}
		return 2;
	}

	// ── 事件映射 ───────────────────────────────────────────────

	/** 只映射引擎真的实现了的事件；其余丢弃（乱传会触发不存在的行为） */
	static function mapEvent(name:String, t:Float, v:Dynamic):Null<CEvent>
	{
		if (v == null) v = {};
		switch (name)
		{
			case 'PlayAnimation':
				var anim:String = strField(v, 'anim');
				if (anim == '') anim = strField(v, 'animation');
				var target:String = strField(v, 'target');
				if (target == '') target = strField(v, 'character');
				if (anim == '') return null;
				return {t: t, name: 'Play Animation', v1: anim, v2: target};
			case 'ChangeCharacter', 'ChangeCharacterCL':
				var who:String = strField(v, 'character');
				var newc:String = strField(v, 'newchar');
				if (newc == '') newc = strField(v, 'newCharacter');
				if (who == '' || newc == '') return null;
				return {t: t, name: 'Change Character', v1: who, v2: newc};
		}
		return null;
	}

	static function groupEvents(events:Array<CEvent>):Array<Dynamic>
	{
		events.sort(function(a:CEvent, b:CEvent):Int
		{
			if (a.t < b.t) return -1;
			if (a.t > b.t) return 1;
			return 0;
		});

		var out:Array<Dynamic> = [];
		var i:Int = 0;
		while (i < events.length)
		{
			var t:Float = Math.round(events[i].t);
			var bucket:Array<Dynamic> = [];
			while (i < events.length && Math.round(events[i].t) == t)
			{
				var one:Array<Dynamic> = [events[i].name, events[i].v1, events[i].v2];
				bucket.push(one);
				i++;
			}
			var entry:Array<Dynamic> = [t, bucket];
			out.push(entry);
		}
		return out;
	}

	// ── 小工具 ─────────────────────────────────────────────────

	static function makeSection(bpm:Float):SwagSection
	{
		return {
			sectionNotes: [],
			sectionBeats: 4,
			mustHitSection: true,
			changeBPM: false,
			bpm: bpm,
			altAnim: false,
			gfSection: false
		};
	}

	static function beatAt(t:Float, tc:Array<BPMChange>, segBeats:Array<Float>):Float
	{
		var idx:Int = 0;
		for (i in 0...tc.length)
		{
			if (tc[i].t <= t) idx = i;
			else break;
		}
		var seg:Float = 60000.0 / tc[idx].bpm;
		return segBeats[idx] + (t - tc[idx].t) / seg;
	}

	static function numField(o:Dynamic, name:String, def:Float):Float
	{
		if (o == null) return def;
		var v:Dynamic = Reflect.field(o, name);
		if (v == null) return def;
		if (!Std.isOfType(v, Float) && !Std.isOfType(v, Int)) return def;
		var f:Float = cast v;
		if (Math.isNaN(f)) return def;
		return f;
	}

	static function strField(o:Dynamic, name:String):String
	{
		if (o == null) return '';
		var v:Dynamic = Reflect.field(o, name);
		if (v == null) return '';
		if (Std.isOfType(v, String)) return cast v;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return Std.string(v);
		return '';
	}

	static function strArray(o:Dynamic, name:String):Array<String>
	{
		var out:Array<String> = [];
		if (o == null) return out;
		var v:Dynamic = Reflect.field(o, name);
		if (v == null || !Std.isOfType(v, Array)) return out;
		for (x in (v:Array<Dynamic>))
		{
			if (x == null) continue;
			if (Std.isOfType(x, String)) out.push(cast x);
			else out.push(Std.string(x));
		}
		return out;
	}
}
