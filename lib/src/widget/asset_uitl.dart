import 'package:flutter/material.dart';

// ignore: avoid_classes_with_only_static_members
class AssetUtil {
  static String getAlumName({Locale? locale, String? name}) {
    if (name == null) {
      return "";
    }
    final String languageCode = locale?.languageCode.toLowerCase() ?? 'en';
    if (languageCode == 'zh') {
      final String? albumName = albumLanguageMap['zh']?[name];
      if (albumName != null) {
        return albumName;
      } else {
        return name;
      }
    } else {
      return name;
    }
    return '';
  }

  static final Map<String, Map<String, String>> albumLanguageMap = {
    // ignore: always_specify_types
    'zh': {
      'Recents': '最近项目',
      'Screenshots': '截屏',
      'Videos': '视频',
      'Bursts': '连拍快照',
      'Favorites': '个人收藏',
      'Live Photos': '实况照片',
      'Long Exposure': '长曝光',
      'Time-lapse': '延时摄影',
      'Portrait': '人像',
      'Panoramas': '全景照片',
      'Selfies': '自拍',
      'Slo-mo': '慢动作',
      //安卓
      'Recent': '最近',
      'Camera': '相机',
      'Movies': 'Movies',
      'Pictures': 'Pictures',
      'Download': '下载',
    },
  };
}

/**
 * Recent 
93%
+
确认
Recent (110)
Camera (28)
Screenshots (2)
Movies (17)
Pictures (6)
Instagram (11)
DCIM (23)
sharelmg (5)
com.mm.foreignmainvideo(2)
Download (1)
com.mm.foreignmarket (3)
com.mm.mainvideo (11)
 */
//[Recents, Screenshots, 拍立淘, Videos, Bursts, Hidden, Favorites, Live Photos, Long Exposure, Time-lapse, Portrait, Panoramas, Selfies, Slo-mo, QQ, QQ, QQ空间, 表情广场, 网易新闻, Animated, 微博, 今日头条, 内涵段子, 小Q画笔, 壁纸精灵, 火萤, 壁纸, VUE, 抖音, 视频壁纸, SendAnywhere, 百度网盘, 简书, TikTok, 最美壁纸, InShot, QQ浏览器, 龙猫工具大师, 哈你, 视频, 滚动截屏, Images, 阿里云盘, Lightroom, Images, Images, 小米智能摄像机 云台版2K365617885, 449680545, 小红书, 天天P图, 美颜相机, DJI Album, 剪映, 秒剪, 龙猫水印大师, 365617885, Piczoo, 手机淘宝]