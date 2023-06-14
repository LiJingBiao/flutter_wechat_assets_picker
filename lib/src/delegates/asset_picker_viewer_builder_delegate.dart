// Copyright 2019 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../constants/custom_scroll_physics.dart';
import '../constants/enums.dart';
import '../constants/extensions.dart';
import '../constants/typedefs.dart';
import '../delegates/asset_picker_text_delegate.dart';
import '../internal/singleton.dart';
import '../provider/asset_picker_provider.dart';
import '../provider/asset_picker_viewer_provider.dart';
import '../widget/asset_picker_viewer.dart';
import '../widget/builder/audio_page_builder.dart';
import '../widget/builder/fade_image_builder.dart';
import '../widget/builder/image_page_builder.dart';
import '../widget/builder/value_listenable_builder_2.dart';
import '../widget/builder/video_page_builder.dart';
import '../widget/scale_text.dart';

abstract class AssetPickerViewerBuilderDelegate<Asset, Path> {
  AssetPickerViewerBuilderDelegate({
    required this.previewAssets,
    required this.themeData,
    required this.currentIndex,
    this.selectorProvider,
    this.provider,
    this.selectedAssets,
    this.maxAssets,
    this.shouldReversePreview = false,
    this.selectPredicate,
  })  : assert(maxAssets == null || maxAssets > 0),
        assert(currentIndex >= 0);

  /// [ChangeNotifier] for photo selector viewer.
  /// 资源预览器的状态保持
  final AssetPickerViewerProvider<Asset>? provider;

  /// Assets provided to preview.
  /// 提供预览的资源
  final List<Asset> previewAssets;

  /// Theme for the viewer.
  /// 主题
  final ThemeData themeData;

  /// Selected assets.
  /// 已选的资源
  final List<Asset>? selectedAssets;

  /// Provider for [AssetPicker].
  /// 资源选择器的状态保持
  final AssetPickerProvider<Asset, Path>? selectorProvider;

  /// Whether the preview sequence is reversed.
  /// 预览时顺序是否为反向
  ///
  /// Usually this will be true when users are previewing on Apple OS and
  /// clicked one item of the asset grid.
  /// 通常用户使用苹果系统时，点击网格内容进行预览，是反向进行预览。
  final bool shouldReversePreview;

  /// {@macro wechat_assets_picker.AssetSelectPredicate}
  final AssetSelectPredicate<Asset>? selectPredicate;

  /// [StreamController] for viewing page index update.
  /// 用于更新当前正在浏览的资源页码的流控制器
  ///
  /// The main purpose is to narrow down build parts when index is changing,
  /// prevent widely [State.setState] and causing other widgets rebuild.
  /// 使用 [StreamController] 的主要目的是缩小页码变化时构建组件的范围，
  /// 防止滥用 [State.setState] 导致其他部件重新构建。
  final StreamController<int> pageStreamController =
      StreamController<int>.broadcast();

  /// The [ScrollController] for the previewing assets list.
  /// 正在预览的资源的 [ScrollController]
  final ScrollController previewingListController = ScrollController();

  /// Whether detail widgets displayed.
  /// 详情部件是否显示
  final ValueNotifier<bool> isDisplayingDetail = ValueNotifier<bool>(true);

  /// The [State] for a viewer.
  /// 预览器的状态实例
  late AssetPickerViewerState<Asset, Path> viewerState;

  /// [AnimationController] for double tap animation.
  /// 双击缩放的动画控制器
  late AnimationController doubleTapAnimationController;

  /// [CurvedAnimation] for double tap.
  /// 双击缩放的动画曲线
  late Animation<double> doubleTapCurveAnimation;

  /// [Animation] for double tap.
  /// 双击缩放的动画
  Animation<double>? doubleTapAnimation;

  /// Callback for double tap.
  /// 双击缩放的回调
  late VoidCallback doubleTapListener;

  /// [PageController] for assets preview [PageView].
  /// 查看图片资源的页面控制器
  ExtendedPageController get pageController => _pageController;
  late final ExtendedPageController _pageController = ExtendedPageController(
    initialPage: currentIndex,
  );

  /// Current previewing index in assets.
  /// 当前查看的索引
  int currentIndex;

  /// Maximum count for asset selection.
  /// 资源选择的最大数量
  final int? maxAssets;

  /// Whether the viewer is under preview mode for selected assets.
  /// 当前是否处于查看已选中资源的模式
  late final bool isSelectedPreviewing = selectedAssets == previewAssets;

  /// Getter for the current asset.
  /// 当前资源的Getter
  Asset get currentAsset => previewAssets.elementAt(currentIndex);

  /// Height for bottom preview widget.
  /// 底栏预览部件的高度
  double get bottomPreviewHeight => 90.0;

  /// Height for bottom bar widget.
  /// 底栏部件的高度
  double get bottomBarHeight => 50.0;

  double get bottomDetailHeight => bottomPreviewHeight + bottomBarHeight;

  /// Whether the current platform is Apple OS.
  /// 当前平台是否为苹果系列系统
  bool get isAppleOS => Platform.isIOS || Platform.isMacOS;

  AssetPickerTextDelegate get textDelegate => Singleton.textDelegate;

  AssetPickerTextDelegate get semanticsTextDelegate =>
      Singleton.textDelegate.semanticsTextDelegate;

  /// Call when viewer is calling [State.initState].
  /// 当预览器调用 [State.initState] 时注册 [State]。
  @mustCallSuper
  void initStateAndTicker(
    covariant AssetPickerViewerState<Asset, Path> state,
    TickerProvider v, // TODO(Alex): Remove this in the next major version.
  ) {
    initAnimations(state);
  }

  /// Call when the viewer is calling [State.didUpdateWidget].
  /// 当预览器调用 [State.didUpdateWidget] 时操作 [State]。
  ///
  /// Since delegates are relatively "Stateless" compare to the
  /// [AssetPickerViewerState], the widget that holds the delegate might changed
  /// when using the viewer as a nested widget, which will construct
  /// a new delegate and only calling [State.didUpdateWidget] at the moment.
  @mustCallSuper
  void didUpdateViewer(
    covariant AssetPickerViewerState<Asset, Path> state,
    covariant AssetPickerViewer<Asset, Path> oldWidget,
    covariant AssetPickerViewer<Asset, Path> newWidget,
  ) {
    // Widgets are useless in the default delegate.
    initAnimations(state);
  }

  /// Keep a dispose method to sync with [State].
  /// 保留一个 dispose 方法与 [State] 同步。
  @mustCallSuper
  void dispose() {
    provider?.dispose();
    pageController.dispose();
    pageStreamController.close();
    previewingListController.dispose();
    selectedNotifier.dispose();
    isDisplayingDetail.dispose();
    doubleTapAnimationController
      ..stop()
      ..reset()
      ..dispose();
  }

  /// Initialize animations related to the zooming preview.
  /// 为缩放预览初始化动画
  void initAnimations(covariant AssetPickerViewerState<Asset, Path> state) {
    viewerState = state;
    doubleTapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: state,
    );
    doubleTapCurveAnimation = CurvedAnimation(
      parent: doubleTapAnimationController,
      curve: Curves.easeInOut,
    );
  }

  /// Produce [OrdinalSortKey] with the fixed name.
  OrdinalSortKey ordinalSortKey(double value) {
    return OrdinalSortKey(value, name: 'AssetPickerViewerBuilderDelegate');
  }

  /// Execute scale animation when double tap.
  /// 双击时执行缩放动画
  void updateAnimation(ExtendedImageGestureState state) {
    final double begin = state.gestureDetails!.totalScale!;
    final double end = state.gestureDetails!.totalScale! == 1.0 ? 3.0 : 1.0;
    final Offset pointerDownPosition = state.pointerDownPosition!;

    doubleTapAnimation?.removeListener(doubleTapListener);
    doubleTapAnimationController
      ..stop()
      ..reset();
    doubleTapListener = () {
      state.handleDoubleTap(
        scale: doubleTapAnimation!.value,
        doubleTapPosition: pointerDownPosition,
      );
    };
    doubleTapAnimation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(doubleTapCurveAnimation)
      ..addListener(doubleTapListener);
    doubleTapAnimationController.forward();
  }

  /// The length getter for selected assets currently.
  /// 当前选中的资源的长度获取
  int get selectedCount => selectedAssets?.length ?? 0;

  /// 是否已经选择了最大数量的资源
  bool get selectedMaximumAssets =>
      selectedAssets != null && selectedAssets!.length == maxAssets;

  /// Construct a notifier to notify
  /// whether if a new asset is selected or unselected.
  /// 构造一个通知器，在新资源选中或取消选中时通知。
  late final ValueNotifier<int> selectedNotifier =
      ValueNotifier<int>(selectedCount);

  void unSelectAsset(Asset entity) {
    provider?.unSelectAsset(entity);
    selectorProvider?.unSelectAsset(entity);
    if (!isSelectedPreviewing) {
      selectedAssets?.remove(entity);
    }
    selectedNotifier.value = selectedCount;
  }

  void selectAsset(Asset entity) {
    if (maxAssets != null && selectedCount >= maxAssets!) {
      return;
    }
    provider?.selectAsset(entity);
    selectorProvider?.selectAsset(entity);
    if (!isSelectedPreviewing) {
      selectedAssets?.add(entity);
    }
    selectedNotifier.value = selectedCount;
  }

  //编辑完替换asset
  void replaceAsset(Asset oldItem, Asset newItem) {
    provider?.replaceAsset(oldItem, newItem);
    selectorProvider?.replaceAsset(oldItem, newItem);
    previewAssets[currentIndex] = newItem;
    selectedAssets?[currentIndex] = newItem;
    //!isSelectedPreviewing
    // if (true) {
    //   if (selectedAssets != null && selectedAssets!.contains(oldItem)) {
    //     int index = selectedAssets!.indexOf(oldItem);
    //     selectedAssets![index] = newItem;
    //   } else {
    //     selectedAssets?.add(newItem);
    //   }
    // }
    // if (previewAssets.contains(oldItem)) {
    //   int index = previewAssets.indexOf(oldItem);
    //   previewAssets[index] = newItem;
    // }
    //previewAssets
    selectedNotifier.value = selectedCount;
    viewerState.setState(() {});
  }

  Future<bool> onChangingSelected(
    BuildContext context,
    Asset asset,
    bool isSelected,
  ) async {
    final bool? selectPredicateResult = await selectPredicate?.call(
      context,
      asset,
      isSelected,
    );
    if (selectPredicateResult == false) {
      return false;
    }
    if (isSelected) {
      unSelectAsset(asset);
    } else {
      selectAsset(asset);
    }
    return true;
  }

  /// Method to switch [isDisplayingDetail].
  /// 切换显示详情状态的方法
  void switchDisplayingDetail({bool? value}) {
    isDisplayingDetail.value = value ?? !isDisplayingDetail.value;
  }

  /// Sync selected assets currently with asset picker provider.
  /// 在预览中当前已选的图片同步到选择器的状态
  @Deprecated('The method is not used by the package anymore')
  Future<bool> syncSelectedAssetsWhenPop() async {
    if (provider?.currentlySelectedAssets != null) {
      selectorProvider?.selectedAssets = provider!.currentlySelectedAssets;
    }
    return true;
  }

  /// Split page builder according to type of asset.
  /// 根据资源类型使用不同的构建页
  Widget assetPageBuilder(BuildContext context, int index);

  /// Common image load state changed callback with [Widget].
  /// 图片加载状态的部件回调
  Widget previewWidgetLoadStateChanged(
    BuildContext context,
    ExtendedImageState state, {
    bool hasLoaded = false,
  }) {
    switch (state.extendedImageLoadState) {
      case LoadState.completed:
        if (hasLoaded) {
          return state.completedWidget;
        }
        return FadeImageBuilder(child: state.completedWidget);
      case LoadState.failed:
        return failedItemBuilder(context);
      case LoadState.loading:
        return const SizedBox.shrink();
    }
  }

  /// The item widget when [AssetEntity.thumbnailData] load failed.
  /// 资源缩略数据加载失败时使用的部件
  Widget failedItemBuilder(BuildContext context) {
    return Center(
      child: ScaleText(
        textDelegate.loadFailed,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18.0),
        semanticsLabel: semanticsTextDelegate.loadFailed,
      ),
    );
  }

  /// Confirm button.
  /// 确认按钮
  Widget confirmButton(BuildContext context);

  /// Select button.
  /// 选择按钮
  Widget selectButton(BuildContext context);

  /// Thumb item widgets in bottom detail.
  /// 底部信息栏单个资源缩略部件
  Widget bottomDetailItemBuilder(BuildContext context, int index);

  /// Detail widget aligned to bottom.
  /// 底部信息部件
  Widget bottomDetailBuilder(BuildContext context);

  /// Yes, the build method.
  /// 没错，是它是它就是它，我们亲爱的 build 方法~
  Widget build(BuildContext context);
}

class DefaultAssetPickerViewerBuilderDelegate
    extends AssetPickerViewerBuilderDelegate<AssetEntity, AssetPathEntity> {
  DefaultAssetPickerViewerBuilderDelegate({
    required super.currentIndex,
    required super.previewAssets,
    required super.themeData,
    super.selectorProvider,
    super.provider,
    super.selectedAssets,
    this.previewThumbnailSize,
    this.specialPickerType,
    super.maxAssets,
    super.shouldReversePreview,
    super.selectPredicate,
    this.deleteVideoAction,
    this.editRoute,
  });

  void Function(BuildContext)? deleteVideoAction;

  //type 0 照片 1视频 lijingbiao
  final Route<dynamic> Function(dynamic file, int type)? editRoute;

  /// Thumb size for the preview of images in the viewer.
  /// 预览时图片的缩略图大小
  final ThumbnailSize? previewThumbnailSize;

  /// The current special picker type for the viewer.
  /// 当前特殊选择类型
  ///
  /// If the type is not null, the title of the viewer will not display.
  /// 如果类型不为空，则标题将不会显示。
  final SpecialPickerType? specialPickerType;

  /// Whether the [SpecialPickerType.wechatMoment] is enabled.
  /// 当前是否为微信朋友圈选择模式
  bool get isWeChatMoment =>
      specialPickerType == SpecialPickerType.wechatMoment;

  /// Whether there are videos in preview/selected assets.
  /// 当前正在预览或已选的资源是否有视频
  bool get hasVideo =>
      previewAssets.any((AssetEntity e) => e.type == AssetType.video) ||
      (selectedAssets?.any((AssetEntity e) => e.type == AssetType.video) ??
          false);

  @override
  Widget assetPageBuilder(BuildContext context, int index) {
    final AssetEntity asset = previewAssets.elementAt(index);
    final Widget builder;
    switch (asset.type) {
      case AssetType.audio:
        builder = AudioPageBuilder(asset: asset);
        break;
      case AssetType.image:
        builder = ImagePageBuilder(
          asset: asset,
          delegate: this,
          previewThumbnailSize: previewThumbnailSize,
        );
        break;
      case AssetType.video:
        builder = VideoPageBuilder(
          asset: asset,
          delegate: this,
          hasOnlyOneVideoAndMoment: isWeChatMoment && hasVideo,
        );
        break;
      case AssetType.other:
        builder = Center(
          child: ScaleText(
            textDelegate.unSupportedAssetType,
            semanticsLabel: semanticsTextDelegate.unSupportedAssetType,
          ),
        );
        break;
    }
    return MergeSemantics(
      child: Consumer<AssetPickerViewerProvider<AssetEntity>?>(
        builder: (
          BuildContext c,
          AssetPickerViewerProvider<AssetEntity>? p,
          Widget? w,
        ) {
          print("😃😃😃😃😃😃😃😃😃：$p");
          final bool isSelected =
              (p?.currentlySelectedAssets ?? selectedAssets)?.contains(asset) ??
                  false;
          String hint = '';
          if (asset.type == AssetType.audio || asset.type == AssetType.video) {
            hint += '${semanticsTextDelegate.sNameDurationLabel}: ';
            hint += textDelegate.durationIndicatorBuilder(asset.videoDuration);
          }
          if (asset.title?.isNotEmpty ?? false) {
            hint += ', ${asset.title}';
          }
          return Semantics(
            label: '${semanticsTextDelegate.semanticTypeLabel(asset.type)}'
                '${index + 1}, '
                '${asset.createDateTime.toString().replaceAll('.000', '')}',
            selected: isSelected,
            hint: hint,
            image:
                asset.type == AssetType.image || asset.type == AssetType.video,
            child: w,
          );
        },
        child: builder,
      ),
    );
  }

  /// Preview item widgets for audios.
  /// 音频的底部预览部件
  Widget _audioPreviewItem(AssetEntity asset) {
    return ColoredBox(
      color: viewerState.context.themeData.dividerColor,
      child: const Center(child: Icon(Icons.audiotrack)),
    );
  }

  /// Preview item widgets for images.
  /// 图片的底部预览部件
  Widget _imagePreviewItem(AssetEntity asset) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: ExtendedImage(
          image: AssetEntityImageProvider(asset, isOriginal: false),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  /// Preview item widgets for video.
  /// 视频的底部预览部件
  Widget _videoPreviewItem(AssetEntity asset) {
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          _imagePreviewItem(asset),
          Center(
            child: Icon(
              Icons.video_library,
              color: themeData.iconTheme.color?.withOpacity(0.54),
            ),
          ),
        ],
      ),
    );
  }

  /// The back button when previewing video in [SpecialPickerType.wechatMoment].
  /// 使用 [SpecialPickerType.wechatMoment] 预览视频时的返回按钮
  Widget momentVideoBackButton(BuildContext context) {
    return PositionedDirectional(
      start: 16,
      top: context.topPadding + 16,
      child: Semantics(
        sortKey: ordinalSortKey(0),
        child: IconButton(
          onPressed: Navigator.of(context).maybePop,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tight(const Size.square(28)),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          iconSize: 18,
          icon: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: themeData.iconTheme.color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.keyboard_return_rounded,
              color: themeData.canvasColor,
            ),
          ),
        ),
      ),
    );
  }

  //selectedNotifier
  @override
  Widget bottomDetailBuilder(BuildContext context) {
    final Color backgroundColor = themeData.primaryColor.withOpacity(.9);
    return ValueListenableBuilder2<bool, int>(
      firstNotifier: isDisplayingDetail,
      secondNotifier: selectedNotifier,
      builder: (_, bool v, __, Widget? child) => AnimatedPositionedDirectional(
        duration: kThemeAnimationDuration,
        curve: Curves.easeInOut,
        bottom: v ? 0 : -(context.bottomPadding + bottomDetailHeight),
        start: 0,
        end: 0,
        height: context.bottomPadding + bottomDetailHeight,
        child: child!,
      ),
      child: CNP<AssetPickerViewerProvider<AssetEntity>?>.value(
        value: provider,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (provider != null)
              ValueListenableBuilder<int>(
                valueListenable: selectedNotifier,
                builder: (_, int count, __) {
                  print("😄😄😄😄😄😄😄😄😄😄😄😄😄$count");
                  return Container(
                    width: count > 0 ? double.maxFinite : 0,
                    height: bottomPreviewHeight,
                    color: backgroundColor,
                    child: ListView.builder(
                      controller: previewingListController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 5.0),
                      physics: const ClampingScrollPhysics(),
                      itemCount: count,
                      itemBuilder: bottomDetailItemBuilder,
                    ),
                  );
                },
              ),
            Container(
              height: bottomBarHeight + context.bottomPadding,
              padding: const EdgeInsets.symmetric(horizontal: 20.0)
                  .copyWith(bottom: context.bottomPadding),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: themeData.canvasColor)),
                color: backgroundColor,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildEditButton(context), //by lijingbiao iOS编辑按钮
                  const Spacer(),
                  if (isAppleOS && (provider != null || isWeChatMoment))
                    confirmButton(context)
                  else
                    selectButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  //从 selectedAssets 获取的小图
  @override
  Widget bottomDetailItemBuilder(BuildContext context, int index) {
    const double padding = 8.0;

    void onTap(AssetEntity asset) {
      final int page;
      if (previewAssets != selectedAssets) {
        page = previewAssets.indexOf(asset);
      } else {
        page = index;
      }
      if (pageController.page == page.toDouble()) {
        return;
      }
      pageController.jumpToPage(page);
      final double offset =
          (index - 0.5) * (bottomPreviewHeight - padding * 3) -
              context.mediaQuery.size.width / 4;
      previewingListController.animateTo(
        math.max(0, offset),
        curve: Curves.ease,
        duration: kThemeChangeDuration,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 2,
      ),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: StreamBuilder<int>(
          initialData: currentIndex,
          stream: pageStreamController.stream,
          builder: (_, AsyncSnapshot<int> snapshot) {
            final AssetEntity asset = selectedAssets!.elementAt(index);
            final bool isViewing = previewAssets[snapshot.data!] == asset;
            final Widget item = () {
              switch (asset.type) {
                case AssetType.image:
                  return _imagePreviewItem(asset);
                case AssetType.video:
                  return _videoPreviewItem(asset);
                case AssetType.audio:
                  return _audioPreviewItem(asset);
                case AssetType.other:
                  return const SizedBox.shrink();
              }
            }();
            return Semantics(
              label: '${semanticsTextDelegate.semanticTypeLabel(asset.type)}'
                  '${index + 1}',
              selected: isViewing,
              onTap: () => onTap(asset),
              onTapHint: semanticsTextDelegate.sActionPreviewHint,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onTap(asset),
                child: Selector<AssetPickerViewerProvider<AssetEntity>?,
                    List<AssetEntity>?>(
                  selector: (_, AssetPickerViewerProvider<AssetEntity>? p) =>
                      p?.currentlySelectedAssets,
                  child: item,
                  builder: (
                    _,
                    List<AssetEntity>? currentlySelectedAssets,
                    Widget? w,
                  ) {
                    final bool isSelected =
                        currentlySelectedAssets?.contains(asset) ?? false;
                    return Stack(
                      children: <Widget>[
                        w!,
                        AnimatedContainer(
                          duration: kThemeAnimationDuration,
                          curve: Curves.easeInOut,
                          decoration: BoxDecoration(
                            border: isViewing
                                ? Border.all(
                                    color: themeData.colorScheme.secondary,
                                    width: 3,
                                  )
                                : null,
                            color: isSelected
                                ? null
                                : themeData.colorScheme.surface
                                    .withOpacity(0.54),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// AppBar widget.
  /// 顶栏部件
  Widget appBar(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDisplayingDetail,
      builder: (_, bool value, Widget? child) => AnimatedPositionedDirectional(
        duration: kThemeAnimationDuration,
        curve: Curves.easeInOut,
        top: value ? 0.0 : -(context.topPadding + kToolbarHeight),
        start: 0.0,
        end: 0.0,
        height: context.topPadding + kToolbarHeight,
        child: child!,
      ),
      child: Container(
        padding: EdgeInsetsDirectional.only(top: context.topPadding),
        color: themeData.canvasColor,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  sortKey: ordinalSortKey(0),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: Navigator.of(context).maybePop,
                  ),
                ),
              ),
            ),
            if (!isAppleOS && specialPickerType == null)
              Expanded(
                child: Center(
                  child: Semantics(
                    sortKey: ordinalSortKey(0.1),
                    child: StreamBuilder<int>(
                      initialData: currentIndex,
                      stream: pageStreamController.stream,
                      builder: (_, AsyncSnapshot<int> snapshot) => ScaleText(
                        '${snapshot.data! + 1}/${previewAssets.length}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (isAppleOS && provider != null)
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Semantics(
                    sortKey: ordinalSortKey(0.2),
                    child: selectButton(context),
                  ),
                ),
              )
            else if (isAppleOS)
              // const Spacer(),
              _buildDeleteButton(context),
            if (!isAppleOS && (provider != null || isWeChatMoment))
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Semantics(
                    sortKey: ordinalSortKey(0.3),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 14),
                      child: confirmButton(context),
                    ),
                  ),
                ),
              )
            else if (!isAppleOS)
              _buildDeleteButton(context),
            // const Spacer(),
          ],
        ),
      ),
    );
  }

  //自定义删除视频 lijingbiao
  Widget _buildDeleteButton(BuildContext context) {
    if (deleteVideoAction == null) {
      return Spacer();
    }
    return Expanded(
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Semantics(
          sortKey: ordinalSortKey(0.6),
          child: IconButton(
              icon: const Icon(Icons.delete),
              tooltip: MaterialLocalizations.of(
                context,
              ).deleteButtonTooltip,
              onPressed: () async {
                deleteVideoAction?.call(context);
              }),
        ),
      ),
    );
  }

  // ' (${provider.currentlySelectedAssets.length}''/' '${selectorProvider!.maxAssets})';
  /// It'll pop with [AssetPickerProvider.selectedAssets] when there are
  /// any assets were chosen. Then, the assets picker will pop too.
  /// 当有资源已选时，点击按钮将把已选资源通过路由返回。
  /// 资源选择器将识别并一同返回。
  @override
  Widget confirmButton(BuildContext context) {
    return CNP<AssetPickerViewerProvider<AssetEntity>?>.value(
      value: provider,
      child: Consumer<AssetPickerViewerProvider<AssetEntity>?>(
        builder: (_, AssetPickerViewerProvider<AssetEntity>? provider, __) {
          assert(
            isWeChatMoment || provider != null,
            'Viewer provider must not be null '
            'when the special type is not WeChat moment.',
          );
          Future<void> onPressed() async {
            if (hasVideo) {
              if (editRoute != null) {
                // ignore: prefer_final_locals
                AssetEntity? newEntity =
                    await Navigator.of(context, rootNavigator: true)
                        .push<AssetEntity?>(
                  editRoute?.call(currentAsset, 1) as Route<AssetEntity?>,
                );
                if (newEntity != null) {
                  Navigator.of(context).maybePop([newEntity]);
                }
              } else {
                Navigator.of(context).pop(<AssetEntity>[currentAsset]);
              }

              return;
            }
            if (provider!.isSelectedNotEmpty) {
              Navigator.of(context).pop(provider.currentlySelectedAssets);
              return;
            }
            if (await onChangingSelected(context, currentAsset, false)) {
              Navigator.of(context).pop(
                selectedAssets ?? <AssetEntity>[currentAsset],
              );
            }
          }

          String buildText() {
            if (isWeChatMoment && hasVideo) {
              return textDelegate.confirm;
            }
            if (provider!.isSelectedNotEmpty) {
              return '${textDelegate.confirm}'
                  ' (${provider.currentlySelectedAssets.length}'
                  '/'
                  '${selectorProvider!.maxAssets})';
            }
            return textDelegate.confirm;
          }

          final bool isButtonEnabled = provider == null ||
              provider.currentlySelectedAssets.isNotEmpty ||
              previewAssets.isEmpty ||
              selectedNotifier.value == 0;
          return MaterialButton(
            minWidth:
                (isWeChatMoment && hasVideo) || provider!.isSelectedNotEmpty
                    ? 48
                    : 20,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: themeData.colorScheme.secondary,
            disabledColor: themeData.dividerColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            onPressed: isButtonEnabled ? onPressed : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            child: ScaleText(
              buildText(),
              style: TextStyle(
                color: themeData.textTheme.bodyLarge?.color,
                fontSize: 17,
                fontWeight: FontWeight.normal,
              ),
              overflow: TextOverflow.fade,
              softWrap: false,
              semanticsLabel: () {
                if (isWeChatMoment && hasVideo) {
                  return semanticsTextDelegate.confirm;
                }
                if (provider!.isSelectedNotEmpty) {
                  return '${semanticsTextDelegate.confirm}'
                      ' (${provider.currentlySelectedAssets.length}'
                      '/'
                      '${selectorProvider!.maxAssets})';
                }
                return semanticsTextDelegate.confirm;
              }(),
            ),
          );
        },
      ),
    );
  }

  //by lijingbiao
  Widget _buildEditButton(BuildContext context) {
    print("isWeChatMoment:${isWeChatMoment}, hasVideo:${hasVideo}");
    if (hasVideo) {
      return SizedBox.shrink();
    }
    if (editRoute == null) {
      return SizedBox.shrink();
    }
    Future<void> editAction() async {
      // ignore: prefer_final_locals
      File? file = await currentAsset.file;
      if (editRoute != null && file != null) {
        AssetEntity? newEntity =
            await Navigator.of(context, rootNavigator: true).push<AssetEntity?>(
          editRoute?.call(file, 0) as Route<AssetEntity?>,
        );
        if (newEntity != null) {
          // newEntity = newEntity.copyWith(
          //     id: currentAsset.id, isFavorite: currentAsset.isFavorite);
          replaceAsset(currentAsset, newEntity);
        }
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: editAction,
      child: Text(
        textDelegate.edit,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }

  /// Select button for apple OS.
  /// 苹果系列系统的选择按钮
  Widget _appleOSSelectButton(
    BuildContext context,
    bool isSelected,
    AssetEntity asset,
  ) {
    if (!isSelected && selectedMaximumAssets) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Feedback.forTap(context);
          onChangingSelected(context, asset, isSelected);
        },
        child: AnimatedContainer(
          duration: kThemeAnimationDuration,
          width: 28.0,
          decoration: BoxDecoration(
            border: !isSelected
                ? Border.all(color: themeData.iconTheme.color!)
                : null,
            color: isSelected ? themeData.colorScheme.secondary : null,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Icon(Icons.check, size: 20.0)),
        ),
      ),
    );
  }

  /// Select button for Android.
  /// 安卓系统的选择按钮
  Widget _androidSelectButton(
    BuildContext context,
    bool isSelected,
    AssetEntity asset,
  ) {
    return Checkbox(
      value: isSelected,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999999),
      ),
      onChanged: (_) => onChangingSelected(context, asset, isSelected),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget selectButton(BuildContext context) {
    return CNP<AssetPickerViewerProvider<AssetEntity>>.value(
      value: provider!,
      builder: (_, Widget? w) => StreamBuilder<int>(
        initialData: currentIndex,
        stream: pageStreamController.stream,
        builder: (BuildContext _, AsyncSnapshot<int> s) {
          final AssetEntity asset = previewAssets.elementAt(s.data!);
          return Selector<AssetPickerViewerProvider<AssetEntity>,
              List<AssetEntity>>(
            selector: (_, AssetPickerViewerProvider<AssetEntity> p) =>
                p.currentlySelectedAssets,
            builder: (BuildContext c, List<AssetEntity> assets, _) {
              final bool isSelected = assets.contains(asset);
              return Semantics(
                selected: isSelected,
                label: semanticsTextDelegate.select,
                onTap: () => onChangingSelected(context, asset, isSelected),
                onTapHint: semanticsTextDelegate.select,
                excludeSemantics: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (isAppleOS)
                      _appleOSSelectButton(c, isSelected, asset)
                    else
                      _androidSelectButton(c, isSelected, asset),
                    if (!isAppleOS)
                      ScaleText(
                        textDelegate.select,
                        style: const TextStyle(fontSize: 17, height: 1),
                        semanticsLabel: semanticsTextDelegate.select,
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  //预览数组 previewAssets
  Widget _pageViewBuilder(BuildContext context) {
    return Semantics(
      sortKey: ordinalSortKey(1),
      child: ExtendedImageGesturePageView.builder(
        physics: previewAssets.length == 1
            ? const CustomClampingScrollPhysics()
            : const CustomBouncingScrollPhysics(),
        controller: pageController,
        itemCount: previewAssets.length,
        itemBuilder: assetPageBuilder,
        reverse: shouldReversePreview,
        onPageChanged: (int index) {
          currentIndex = index;
          pageStreamController.add(index);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themeData,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: themeData.appBarTheme.systemOverlayStyle ??
            (themeData.effectiveBrightness.isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark),
        child: Material(
          color: themeData.colorScheme.onSecondary,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _pageViewBuilder(context)),
              if (isWeChatMoment && hasVideo) ...<Widget>[
                momentVideoBackButton(context),
                PositionedDirectional(
                  end: 16,
                  bottom: context.bottomPadding + 16,
                  child: confirmButton(context),
                ),
              ] else ...<Widget>[
                appBar(context),
                if (selectedAssets != null ||
                    (isWeChatMoment && hasVideo && isAppleOS))
                  bottomDetailBuilder(context),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
