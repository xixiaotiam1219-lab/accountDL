import * as image_cropper from "@candies/image_cropper";
import { ImageCropper } from "@candies/image_cropper";
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { Luban, LubanUtils } from '@ark/luban';

/**
 * 图片裁剪 Sheet 组件
 * 使用 @candies/image_cropper 实现 1:1 交互式裁剪
 */
@Component
export struct ImageCropSheet {
  @State imageSource: image.ImageSource | undefined = undefined;
  @State isLoading: boolean = true;
  
  // 外部传入配置
  cropRatio: number | undefined = undefined; 
  @Prop imageOpacity: number = 1.0;
  @Prop title: string = '裁剪图标';
  
  private controller: image_cropper.ImageCropperController = new image_cropper.ImageCropperController();
  @State config: image_cropper.ImageCropperConfig = new image_cropper.ImageCropperConfig({
        maxScale: 8,
        cropRectPadding: image_cropper.geometry.EdgeInsets.all(20),
        controller: this.controller,
        initCropRectType: image_cropper.InitCropRectType.imageRect,
        cropAspectRatio: image_cropper.CropAspectRatios.ratio1_1, // Initial safe default
  });
  
  // 外部传入的参数
  sourceUri: string = '';
  onComplete?: (croppedUri: string) => void;
  onCancel?: () => void;

  aboutToAppear(): void {
    // Re-initialize config with actual props
    this.config = new image_cropper.ImageCropperConfig({
        maxScale: 8,
        cropRectPadding: image_cropper.geometry.EdgeInsets.all(20),
        controller: this.controller,
        initCropRectType: image_cropper.InitCropRectType.imageRect,
        cropAspectRatio: this.cropRatio ?? image_cropper.CropAspectRatios.ratio1_1,
    });
    this.loadImage();
  }

  private async loadImage(): Promise<void> {
    try {
      if (!this.sourceUri) {
        this.isLoading = false;
        return;
      }
      const file = await fileIo.open(this.sourceUri, fileIo.OpenMode.READ_ONLY);
      this.imageSource = image.createImageSource(file.fd);
      this.isLoading = false;
    } catch (e) {
      console.error('[ImageCrop] Load image failed:', e);
      this.isLoading = false;
    }
  }

  private async cropAndSave(): Promise<void> {
    try {
      const pixelMap = await this.controller.getCroppedImage();
      if (!pixelMap) {
        console.error('[ImageCrop] Get cropped image failed');
        return;
      }
      
      const context = getContext(this) as common.UIAbilityContext;
      const iconDir = `${context.filesDir}/icons`;
      
      try {
        await fileIo.mkdir(iconDir);
      } catch (e) {
        // 目录可能已存在
      }
      
      // 1. 先保存裁剪后的原图
      const tempFileName = `temp_${Date.now()}.png`;
      const tempPath = `${iconDir}/${tempFileName}`;
      const tempFile = await fileIo.open(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      
      // 编码为 PNG（保留透明度）
      const imagePacker = image.createImagePacker();
      const packData = await imagePacker.packing(pixelMap, { format: 'image/png', quality: 100 });
      await fileIo.write(tempFile.fd, packData);
      await fileIo.close(tempFile);
      
      // 2. 直接使用生成的 PNG 文件，跳过 Luban 压缩以防止透明度丢失或格式转换
      // Luban (Luban-Harmony) 可能默认转换为 JPG 或处理 Alpha 通道不完美，
      // 为了保证自定义背景图的这确显示（透明背景），直接保存原图。
      // 注意：这可能会导致文件稍大，但对于背景图来说通常可以接受。

      const targetFileName = `icon_${Date.now()}.png`;
      const targetPath = `${iconDir}/${targetFileName}`;

      try {
        // 将临时文件移动/重命名为最终文件
        await fileIo.moveFile(tempPath, targetPath);
        
        // 如果 moveFile 失败（跨设备/分区等极少数情况），回退到复制+删除
        // 但在应用沙箱内通常没问题。
      } catch (moveErr) {
         // Fallback copy
         fileIo.copyFileSync(tempPath, targetPath);
         try { fileIo.unlinkSync(tempPath); } catch (e) {}
      }

      const savedUri = `file://${targetPath}`;
      console.info(`[ImageCrop] Saved PNG (Uncompressed) to: ${savedUri}`);
      
      // 回调
      if (this.onComplete) {
        this.onComplete(savedUri);
      }
      
    } catch (e) {
      console.error('[ImageCrop] Crop and save failed:', e);
    }
  }

  build() {
    Column() {
      // ... (Title Bar unchanged)
      Row() {
        Button('取消')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })
        
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        Button('完成')
          .fontSize(14)
          .fontColor($r('app.color.brand_color'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.cropAndSave();
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.imageSource) {
        // 裁剪区域
        ImageCropper({
          image: this.imageSource,
          config: this.config,
        })
          .width('100%')
          .layoutWeight(1)
          .opacity(this.imageOpacity) // Apply opacity here
        
        // 底部操作栏
        Row({ space: 48 }) {
          // 旋转按钮
          Column() {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
              .fontSize(24)
              .fontColor([$r('app.color.text_primary')])
            Text('旋转')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .onClick(() => {
            this.controller.rotate({ animation: true });
          })
          
          // 重置按钮
          Column() {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(24)
              .fontColor([$r('app.color.text_primary')])
            Text('重置')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .onClick(() => {
            this.controller.reset();
          })
        }
        .width('100%')
        .height(80)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text('加载图片失败')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
