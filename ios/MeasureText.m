#import "MeasureText.h"

#if __has_include(<React/RCTConvert.h>)
#import <React/RCTConvert.h>
#import <React/RCTFont.h>
#import <React/RCTUtils.h>
#else
#import "React/RCTConvert.h"   // Required when used as a Pod in a Swift project
#import "React/RCTFont.h"
#import "React/RCTUtils.h"
#endif

#import <CoreText/CoreText.h>

static NSString *const E_MISSING_TEXT = @"E_MISSING_TEXT";
static NSString *const E_INVALID_FONT_SPEC = @"E_INVALID_FONT_SPEC";
static NSString *const E_INVALID_TEXTSTYLE = @"E_INVALID_TEXTSTYLE";
static NSString *const E_INVALID_FONTFAMILY = @"E_INVALID_FONTFAMILY";

static inline BOOL isNull(id str) {
    return !str || str == (id) kCFNull;
}

static inline CGFloat CGFloatValueFrom(NSNumber * _Nullable num) {
#if CGFLOAT_IS_DOUBLE
    return num ? num.doubleValue : NAN;
#else
    return num ? num.floatValue : NAN;
#endif
}

#define A_SIZE(x) (sizeof (x)/sizeof (x)[0])



@implementation MeasureText

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

// Because the exported constants
+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

// Example method
// See // https://reactnative.dev/docs/native-modules-ios
RCT_REMAP_METHOD(multiply,
                 multiplyWithA:(nonnull NSNumber*)a withB:(nonnull NSNumber*)b
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
{
    NSNumber *result = @([a floatValue] * [b floatValue]);
    
    resolve(result);
}

RCT_EXPORT_METHOD(measure:(NSDictionary * _Nullable)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    // RCTConvert will return nil if the `options` object was not received.
    NSString *const _Nullable text = [RCTConvert NSString:options[@"text"]];
    if (isNull(text)) {
        reject(E_MISSING_TEXT, @"Missing required text.", nil);
        return;
    }
    
    // Allow empty text without generating error
    // ~~TODO~~: Return the same height as RN. @completed(v2.0.1)
    if (!text.length) {
        resolve(@{
            @"width": @0,
            @"height": @14,
            @"lastLineWidth": @0,
            @"lineCount": @0,
                });
        return;
    }
    
    // We cann't use RCTConvert since it does not handle font scaling and RN
    // does not scale the font if a custom delegate has been defined to create.
    UIFont *const _Nullable font = [self scaledUIFontFromUserSpecs:options];
    if (!font) {
        reject(E_INVALID_FONT_SPEC, @"Invalid font specification.", nil);
        return;
    }
    
    // Allow the user to specify the width or height (both optionals).
    const CGFloat optWidth = CGFloatValueFrom(options[@"width"]);
    const CGFloat maxWidth = isnan(optWidth) || isinf(optWidth) ? CGFLOAT_MAX : optWidth;
    const CGSize maxSize = CGSizeMake(maxWidth, CGFLOAT_MAX);
    
    // Create attributes for the font and the optional letter spacing.
    const CGFloat letterSpacing = CGFloatValueFrom(options[@"letterSpacing"]);
    NSDictionary<NSAttributedStringKey,id> *const attributes = isnan(letterSpacing)
    ? @{NSFontAttributeName: font}
    : @{NSFontAttributeName: font, NSKernAttributeName: @(letterSpacing)};
    
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:maxSize];
    textContainer.lineFragmentPadding = 0.0;
    textContainer.lineBreakMode = NSLineBreakByClipping; // no maxlines support
    
    NSLayoutManager *layoutManager = [NSLayoutManager new];
    [layoutManager addTextContainer:textContainer];
    layoutManager.allowsNonContiguousLayout = YES;      // 'cause lastLineWidth
    
    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:text attributes:attributes];
    [textStorage addLayoutManager:layoutManager];
    
    [layoutManager ensureLayoutForTextContainer:textContainer];
    CGSize size = [layoutManager usedRectForTextContainer:textContainer].size;
    if (!isnan(letterSpacing) && letterSpacing < 0) {
        size.width -= letterSpacing;
    }
    
    const CGFloat epsilon = 0.001;
    const CGFloat width = MIN(RCTCeilPixelValue(size.width + epsilon), maxSize.width);
    const CGFloat height = MIN(RCTCeilPixelValue(size.height + epsilon), maxSize.height);
    const NSInteger lineCount = [self getLineCount:layoutManager];
    
    NSMutableDictionary *result = [[NSMutableDictionary alloc]
                                   initWithObjectsAndKeys:@(width), @"width",
                                   @(height), @"height",
                                   @(lineCount), @"lineCount",
                                   nil];
    
    if ([options[@"usePreciseWidth"] boolValue]) {
        const CGFloat lastIndex = layoutManager.numberOfGlyphs - 1;
        const CGSize lastSize = [layoutManager lineFragmentUsedRectForGlyphAtIndex:lastIndex
                                                                    effectiveRange:nil].size;
        [result setValue:@(lastSize.width) forKey:@"lastLineWidth"];
    }
    
    NSMutableArray<NSNumber *> *lineInfo = [self getLineInfo:layoutManager in:textContainer str:text lineNo:lineCount options:options];
    if (lineInfo) {
        [result setValue:lineInfo forKey:@"lineInfo"];
    }
    
    resolve(result);
}
//
// ============================================================================
//  Non-exposed instance & static methods
// ============================================================================
//

/**
 * Get extended info for a given line number.
 * @since v2.1.0
 */
- (NSInteger)getLineCount:(NSLayoutManager *)layoutManager {
    NSRange lineRange;
    NSUInteger glyphCount = layoutManager.numberOfGlyphs;
    NSInteger lineCount = 0;
    
    for (NSUInteger index = 0; index < glyphCount; lineCount++) {
        [layoutManager
         lineFragmentUsedRectForGlyphAtIndex:index effectiveRange:&lineRange withoutAdditionalLayout:YES];
        index = NSMaxRange(lineRange);
    }
    
    return lineCount;
}

/**
 * Get extended info for a given line number.
 * @since v2.1.0
 */
- (NSMutableArray *)getLineInfo:(NSLayoutManager *)layoutManager in:(NSTextContainer *)textContainer str:(NSString *)str lineNo:(NSInteger)lineTotal options:(NSDictionary * _Nullable)options {
    NSMutableArray<NSNumber *> *lineInfo = [[NSMutableArray alloc] initWithCapacity:lineTotal];
    CGRect lineRect = CGRectZero;
    NSRange lineRange;
    NSUInteger glyphCount = layoutManager.numberOfGlyphs;
    NSInteger lineCount = 0;
    
    
    for (NSUInteger index = 0; index < glyphCount; lineCount++) {
        lineRect = [layoutManager
                    lineFragmentUsedRectForGlyphAtIndex:index
                    effectiveRange:&lineRange
                    withoutAdditionalLayout:YES];
        index = NSMaxRange(lineRange);
        
        NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        NSRange charRange = [layoutManager characterRangeForGlyphRange:lineRange actualGlyphRange:nil];
        NSUInteger start = charRange.location;
        index = NSMaxRange(charRange);
        /*
         Get the trimmed range of chars for the glyph range, to be consistent
         w/android, but the width here will include the trailing whitespace.
         */
        
        NSMutableArray<NSNumber *> *charWidths = [[NSMutableArray alloc] initWithCapacity:(index - start)];
        if ([options[@"useLineWidth"] boolValue]) {
            /*while (index > start && [ws characterIsMember:[str characterAtIndex:index - 1]]) {
             index--;
             }*/
            for (NSUInteger j = 0; j < (index - start); j++) {
                CGRect boundingRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(lineRange.location + j, 1) inTextContainer:textContainer];
                const CGFloat boundingWidth = boundingRect.size.width;
                charWidths[j] = @(boundingWidth);
            }
        }
        NSDictionary *line =   @{
            @"line": @(lineCount),
            @"start": @(start),
            @"end": @(index),
            @"width": @(lineRect.size.width),
            @"charWidths": charWidths
        };
        
        lineInfo[lineCount] = line;
        
    }
    
    return lineInfo;
}

/**
 * Create a scaled font based on the given specs.
 *
 * TODO:
 * This method is used instead of [RCTConvert UIFont] to support the omission
 * of scaling when a custom delegate has been defined for font's creation.
 */
- (UIFont * _Nullable)scaledUIFontFromUserSpecs:(const NSDictionary *)specs
{
    const id allowFontScalingSrc = specs[@"allowFontScaling"];
    const BOOL allowFontScaling = allowFontScalingSrc ? [allowFontScalingSrc boolValue] : YES;
    const CGFloat scaleMultiplier =
    allowFontScaling && _bridge ? _bridge.accessibilityManager.multiplier : 1.0;
    
    return [self UIFontFromUserSpecs:specs withScale:scaleMultiplier];
}

/**
 * Create a font based on the given specs.
 */
- (UIFont * _Nullable)UIFontFromUserSpecs:(const NSDictionary *)specs
                                withScale:(CGFloat)scaleMultiplier
{
    return [RCTFont updateFont:nil
                    withFamily:[RCTConvert NSString:specs[@"fontFamily"]]
                          size:[RCTConvert NSNumber:specs[@"fontSize"]]
                        weight:[RCTConvert NSString:specs[@"fontWeight"]]
                         style:[RCTConvert NSString:specs[@"fontStyle"]]
                       variant:[RCTConvert NSStringArray:specs[@"fontVariant"]]
               scaleMultiplier:scaleMultiplier];
}



@end
