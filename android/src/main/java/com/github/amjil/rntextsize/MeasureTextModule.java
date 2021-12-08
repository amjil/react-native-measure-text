package com.github.amjil.rntextsize;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import javax.annotation.Nullable;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.module.annotations.ReactModule;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.uimanager.DisplayMetricsHolder;

import android.graphics.Path;
import android.graphics.RectF;
import android.os.Build;
import android.text.BoringLayout;
import android.text.Layout;
import android.text.SpannableString;
import android.text.PrecomputedText;
import android.text.StaticLayout;
import android.text.TextPaint;

@ReactModule(name = MeasureTextModule.NAME)
public class MeasureTextModule extends ReactContextBaseJavaModule {
  public static final String NAME = "MeasureText";
  private static final float SPACING_ADDITION = 0f;
  private static final float SPACING_MULTIPLIER = 1f;

  private static final String E_MISSING_TEXT = "E_MISSING_TEXT";
  private static final String E_MISSING_WIDTH = "E_MISSING_WIDTH";
  private static final String E_INVALID_SIZES = "E_INVALID_SIZES";
  private static final String E_INVALID_TYPE = "E_INVALID_TYPE";
  private static final String E_MISSING_PARAMETER = "E_MISSING_PARAMETER";
  private static final String E_UNKNOWN_ERROR = "E_UNKNOWN_ERROR";

  private final ReactApplicationContext mReactContext;

  public MeasureTextModule(ReactApplicationContext reactContext) {
    super(reactContext);
    mReactContext = reactContext;
  }

  @Override
  @NonNull
  public String getName() {
    return NAME;
  }


  // Example method
  // See https://reactnative.dev/docs/native-modules-android
  @ReactMethod
  public void multiply(int a, int b, Promise promise) {

    promise.resolve(a * b);
  }

  @RequiresApi(api = Build.VERSION_CODES.P)
  @ReactMethod
  // @ReactMethod(isBlockingSynchronousMethod = true)
  public void measureChars(@Nullable final ReadableMap specs, Promise promise) {
    final MeasureTextConf conf = getConf(specs, true);
    if (conf == null) {
      return;
    }

    final String _text = conf.getString("text");
    if (_text == null) {
      promise.reject(E_MISSING_TEXT, "Missing required text.");
      return;
    }

    final float density = getCurrentDensity();


    final SpannableString text = (SpannableString) MeasureTextSpannedText
      .spannedFromSpecsAndText(mReactContext, conf, new SpannableString(_text));

    final TextPaint textPaint = new TextPaint(TextPaint.ANTI_ALIAS_FLAG);
    PrecomputedText.Params params = (new PrecomputedText.Params.Builder(textPaint)).build();
    PrecomputedText preText = PrecomputedText.create(text, params);

    final WritableArray result = Arguments.createArray();
    for (int i = 0; i < preText.length(); i++) {
      double width = preText.getWidth(i, i + 1) / density;
      result.pushDouble(width);
    }
    promise.resolve(result);


  }

  // @ReactMethod
  @ReactMethod(isBlockingSynchronousMethod = true)
  // public void measure(@Nullable final ReadableMap specs, Promise promise) {
  public WritableMap measure(@Nullable final ReadableMap specs) {
    final MeasureTextConf conf = getConf(specs, true);
    if (conf == null) {
      return null;
    }

    final String _text = conf.getString("text");
    if (_text == null) {
      return null;
    }

    final float density = getCurrentDensity();
    final float width = conf.getWidth(density);
    final boolean includeFontPadding = conf.includeFontPadding;

    final WritableMap result = Arguments.createMap();
    if (_text.isEmpty()) {
      result.putInt("width", 0);
      result.putDouble("height", minimalHeight(density, includeFontPadding));
      result.putInt("lastLineWidth", 0);
      result.putInt("lineCount", 0);
      return result;
    }

    final SpannableString text = (SpannableString) MeasureTextSpannedText
      .spannedFromSpecsAndText(mReactContext, conf, new SpannableString(_text));


    final TextPaint textPaint = new TextPaint(TextPaint.ANTI_ALIAS_FLAG);
    Layout layout = null;
    try {
      final BoringLayout.Metrics boring = BoringLayout.isBoring(text, textPaint);
      int hintWidth = (int) width;

      if (boring == null) {
        // Not boring, ie. the text is multiline or contains unicode characters.
        final float desiredWidth = Layout.getDesiredWidth(text, textPaint);
        if (desiredWidth <= width) {
          hintWidth = (int) Math.ceil(desiredWidth);
        }
      } else if (boring.width <= width) {
        // Single-line and width unknown or bigger than the width of the text.
        layout = BoringLayout.make(
          text,
          textPaint,
          boring.width,
          Layout.Alignment.ALIGN_NORMAL,
          SPACING_MULTIPLIER,
          SPACING_ADDITION,
          boring,
          includeFontPadding);
      }

      if (layout == null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          layout = StaticLayout.Builder.obtain(text, 0, text.length(), textPaint, hintWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setBreakStrategy(conf.getTextBreakStrategy())
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NORMAL)
            .setIncludePad(includeFontPadding)
            .setLineSpacing(SPACING_ADDITION, SPACING_MULTIPLIER)
            .build();
        } else {
          layout = new StaticLayout(
            text,
            textPaint,
            hintWidth,
            Layout.Alignment.ALIGN_NORMAL,
            SPACING_MULTIPLIER,
            SPACING_ADDITION,
            includeFontPadding
          );
        }
      }

      final int lineCount = layout.getLineCount();
      float rectWidth;

      if (conf.getBooleanOrTrue("usePreciseWidth")) {
        float lastWidth = 0f;
        // Layout.getWidth() returns the configured max width, we must
        // go slow to get the used one (and with the text trimmed).
        rectWidth = 0f;
        for (int i = 0; i < lineCount; i++) {
          lastWidth = layout.getLineMax(i);
          if (lastWidth > rectWidth) {
            rectWidth = lastWidth;
          }
        }
        result.putDouble("lastLineWidth", lastWidth / density);
      } else {
        rectWidth = layout.getWidth();
      }

      double textWidth = Math.min(rectWidth / density, width);

      result.putDouble("width", textWidth);
      result.putDouble("height", layout.getHeight() / density);
      result.putInt("lineCount", lineCount);

      if (conf.getBooleanOrTrue("useCharsWidth")) {
        WritableArray lineInfo = Arguments.createArray();
        for(int i = 0; i < lineCount; i++){
          int lineStart = layout.getLineStart(i);
          int lineEnd = layout.getLineEnd(i);

          double lineWidth = layout.getLineMax(i) / density;
          WritableMap line = Arguments.createMap();

          line.putInt("line", i);
          line.putInt("start", lineStart);
          line.putInt("end", lineEnd);
          line.putDouble("width", lineWidth);


          WritableArray charWidthArray = Arguments.createArray();
          double currentWidth = 0.0d;
          for(int j = lineStart; j < lineEnd; j++) {

            if (currentWidth < lineWidth) {
              Path selectPath = new Path();
              layout.getSelectionPath(j, j + 1, selectPath);

              RectF selectRect = new RectF();
              selectPath.computeBounds(selectRect, true);
              if(textWidth > selectRect.width() / density){
                charWidthArray.pushDouble(selectRect.width() / density);
              } else {
                charWidthArray.pushDouble(0);
              }

              currentWidth += selectRect.width() / density;
            } else {
              charWidthArray.pushDouble(0);
            }


          }
          line.putArray("charWidths", charWidthArray);

          lineInfo.pushMap(line);
        }


        result.putArray("lineInfo", lineInfo);
      }
      // promise.resolve(result);
      return result;
    } catch (Exception e) {
      // promise.reject(E_UNKNOWN_ERROR, e);
      return null;
    }
  }

  public static native int nativeMultiply(int a, int b);

  public static native int nativeMeasure(@Nullable final ReadableMap specs);


  // ============================================================================
  //
  //      Non-exposed instance & static methods
  //
  // ============================================================================

  @Nullable
  private MeasureTextConf getConf(final ReadableMap specs, boolean forText) {
    if (specs == null) {
      return null;
    }
    return new MeasureTextConf(specs, forText);
  }

  @Nullable
  private MeasureTextConf getConf(final ReadableMap specs) {
    return getConf(specs, false);
  }

  /**
   * RN consistently sets the height at 14dp divided by the density
   * plus 1 if includeFontPadding when text is empty, so we do the same.
   */
  private double minimalHeight(final float density, final boolean includeFontPadding) {
    final double height = 14.0 / density;
    return includeFontPadding ? height + 1.0 : height;
  }

  /**
   * Retuns the current density.
   */
  @SuppressWarnings("deprecation")
  public float getCurrentDensity() {
    return DisplayMetricsHolder.getWindowDisplayMetrics().density;
  }
}
