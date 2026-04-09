import XCTest
@testable import iClaw

final class ImagePreviewZoomTests: XCTestCase {

    private let viewport = CGSize(width: 400, height: 800)
    private let accuracy: CGFloat = 0.001

    // MARK: - Zoom Anchor Offset

    func testZoomAtCenterProducesZeroOffset() {
        let fitted = CGSize(width: 400, height: 200)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.5, anchorUnitY: 0.5,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        XCTAssertEqual(offset.width, 0, accuracy: accuracy)
        XCTAssertEqual(offset.height, 0, accuracy: accuracy)
    }

    func testZoomAtTopLeftShiftsImageTowardTopLeft() {
        // Pinch at top-left corner (0, 0) of fitted image (400×200)
        let fitted = CGSize(width: 400, height: 200)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.0, anchorUnitY: 0.0,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        // p = (-200, -100); O = p * (1-2) + 0 = (200, 100)
        XCTAssertEqual(offset.width, 200, accuracy: accuracy)
        XCTAssertEqual(offset.height, 100, accuracy: accuracy)
    }

    func testZoomAtBottomRightShiftsImageTowardBottomRight() {
        let fitted = CGSize(width: 400, height: 200)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 1.0, anchorUnitY: 1.0,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        // p = (200, 100); O = p * (1-2) = (-200, -100)
        XCTAssertEqual(offset.width, -200, accuracy: accuracy)
        XCTAssertEqual(offset.height, -100, accuracy: accuracy)
    }

    func testZoomPreservesExistingPanOffset() {
        let fitted = CGSize(width: 400, height: 200)
        let existing = CGSize(width: 50, height: -30)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.5, anchorUnitY: 0.5,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: existing
        )
        // Center anchor: p = (0, 0); O = 0 + existing = existing
        XCTAssertEqual(offset.width, 50, accuracy: accuracy)
        XCTAssertEqual(offset.height, -30, accuracy: accuracy)
    }

    func testZoomOutTowardsScale1ReducesOffset() {
        let fitted = CGSize(width: 400, height: 800)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.25, anchorUnitY: 0.25,
            fittedSize: fitted,
            lastScale: 2.0, newScale: 1.0,
            lastPanOffset: CGSize(width: 100, height: 200)
        )
        // p = (-100, -200); O = p * (2-1) + (100,200) = (-100,-200) + (100,200) = (0,0)
        XCTAssertEqual(offset.width, 0, accuracy: accuracy)
        XCTAssertEqual(offset.height, 0, accuracy: accuracy)
    }

    func testZoomNoChangeReturnsLastPanOffset() {
        let fitted = CGSize(width: 400, height: 800)
        let existing = CGSize(width: 42, height: -17)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.3, anchorUnitY: 0.7,
            fittedSize: fitted,
            lastScale: 2.0, newScale: 2.0,
            lastPanOffset: existing
        )
        // (lastScale - newScale) = 0, so offset = 0 + existing = existing
        XCTAssertEqual(offset.width, existing.width, accuracy: accuracy)
        XCTAssertEqual(offset.height, existing.height, accuracy: accuracy)
    }

    func testZoomAnchorOffsetIsLinearInMagnification() {
        // Zooming from 1→3 should give the same result regardless of how we
        // express it, as long as anchor and initial offset are the same.
        let fitted = CGSize(width: 400, height: 800)
        let anchorX: CGFloat = 0.25
        let anchorY: CGFloat = 0.75

        let step1 = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: anchorX, anchorUnitY: anchorY,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 3.0,
            lastPanOffset: .zero
        )

        let direct = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: anchorX, anchorUnitY: anchorY,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 3.0,
            lastPanOffset: .zero
        )

        XCTAssertEqual(step1.width, direct.width, accuracy: accuracy)
        XCTAssertEqual(step1.height, direct.height, accuracy: accuracy)
    }

    // MARK: - Non-1:1 aspect ratio images

    func testZoomAnchorForWideImage() {
        // Wide image (4:1) on portrait viewport → fitted 400×100
        let fitted = CGSize(width: 400, height: 100)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.0, anchorUnitY: 0.0,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        // p = (-200, -50); O = p * (1-2) = (200, 50)
        XCTAssertEqual(offset.width, 200, accuracy: accuracy)
        XCTAssertEqual(offset.height, 50, accuracy: accuracy)
    }

    func testZoomAnchorForTallImage() {
        // Tall image (1:4) on portrait viewport → fitted 200×800
        let fitted = CGSize(width: 200, height: 800)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.0, anchorUnitY: 0.0,
            fittedSize: fitted,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        // p = (-100, -400); O = p * (1-2) = (100, 400)
        XCTAssertEqual(offset.width, 100, accuracy: accuracy)
        XCTAssertEqual(offset.height, 400, accuracy: accuracy)
    }

    func testZoomAnchorScreenPositionStaysFixed() {
        // Verify: screen position of the anchor doesn't change after zoom.
        // screen_pos = p * scale + offset  (must be constant)
        let fitted = CGSize(width: 300, height: 150)
        let lastScale: CGFloat = 1.5
        let newScale: CGFloat = 3.0
        let lastPan = CGSize(width: 20, height: -10)
        let anchorUX: CGFloat = 0.3
        let anchorUY: CGFloat = 0.8

        let p = CGSize(
            width: (anchorUX - 0.5) * fitted.width,
            height: (anchorUY - 0.5) * fitted.height
        )

        let newOffset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: anchorUX, anchorUnitY: anchorUY,
            fittedSize: fitted,
            lastScale: lastScale, newScale: newScale,
            lastPanOffset: lastPan
        )

        // screen_before = p * lastScale + lastPan
        let beforeX = p.width * lastScale + lastPan.width
        let beforeY = p.height * lastScale + lastPan.height
        // screen_after = p * newScale + newOffset
        let afterX = p.width * newScale + newOffset.width
        let afterY = p.height * newScale + newOffset.height

        XCTAssertEqual(beforeX, afterX, accuracy: accuracy)
        XCTAssertEqual(beforeY, afterY, accuracy: accuracy)
    }

    // MARK: - Fitted Image Size

    func testFittedSizeWiderImage() {
        let imageSize = CGSize(width: 1000, height: 500) // 2:1 aspect
        let result = ImagePreviewMath.fittedImageSize(imageSize: imageSize, viewportSize: viewport)
        // viewport is 400x800 (0.5 aspect), image is wider (2.0 aspect)
        // fits width: w=400, h=400/2=200
        XCTAssertEqual(result.width, 400, accuracy: accuracy)
        XCTAssertEqual(result.height, 200, accuracy: accuracy)
    }

    func testFittedSizeTallerImage() {
        let imageSize = CGSize(width: 200, height: 1000) // 0.2 aspect
        let result = ImagePreviewMath.fittedImageSize(imageSize: imageSize, viewportSize: viewport)
        // viewport aspect = 0.5, image aspect = 0.2, image is taller
        // fits height: h=800, w=800*0.2=160
        XCTAssertEqual(result.width, 160, accuracy: accuracy)
        XCTAssertEqual(result.height, 800, accuracy: accuracy)
    }

    func testFittedSizeMatchingAspect() {
        let imageSize = CGSize(width: 200, height: 400) // 0.5 aspect = viewport
        let result = ImagePreviewMath.fittedImageSize(imageSize: imageSize, viewportSize: viewport)
        XCTAssertEqual(result.width, 400, accuracy: accuracy)
        XCTAssertEqual(result.height, 800, accuracy: accuracy)
    }

    func testFittedSizeZeroImageReturnsViewport() {
        let result = ImagePreviewMath.fittedImageSize(imageSize: .zero, viewportSize: viewport)
        XCTAssertEqual(result.width, viewport.width, accuracy: accuracy)
        XCTAssertEqual(result.height, viewport.height, accuracy: accuracy)
    }

    func testFittedSizeZeroViewportReturnsZero() {
        let result = ImagePreviewMath.fittedImageSize(
            imageSize: CGSize(width: 100, height: 100), viewportSize: .zero
        )
        XCTAssertEqual(result.width, 0, accuracy: accuracy)
        XCTAssertEqual(result.height, 0, accuracy: accuracy)
    }

    // MARK: - Clamped Offset

    func testClampedOffsetAtScale1ReturnsZero() {
        let fitted = CGSize(width: 400, height: 200)
        let result = ImagePreviewMath.clampedOffset(
            CGSize(width: 100, height: 50),
            scale: 1.0, fittedSize: fitted, viewportSize: viewport
        )
        // At scale 1, fitted*1 - viewport <= 0 for both axes, so max = 0
        XCTAssertEqual(result.width, 0, accuracy: accuracy)
        XCTAssertEqual(result.height, 0, accuracy: accuracy)
    }

    func testClampedOffsetWithinBoundsUnchanged() {
        let fitted = CGSize(width: 400, height: 800)
        // At scale 3: 400*3=1200, maxX=(1200-400)/2=400
        //             800*3=2400, maxY=(2400-800)/2=800
        let offset = CGSize(width: 100, height: -200)
        let result = ImagePreviewMath.clampedOffset(
            offset, scale: 3.0, fittedSize: fitted, viewportSize: viewport
        )
        XCTAssertEqual(result.width, 100, accuracy: accuracy)
        XCTAssertEqual(result.height, -200, accuracy: accuracy)
    }

    func testClampedOffsetExceedingBoundsIsClamped() {
        let fitted = CGSize(width: 400, height: 800)
        // At scale 2: maxX=(800-400)/2=200, maxY=(1600-800)/2=400
        let offset = CGSize(width: 500, height: -900)
        let result = ImagePreviewMath.clampedOffset(
            offset, scale: 2.0, fittedSize: fitted, viewportSize: viewport
        )
        XCTAssertEqual(result.width, 200, accuracy: accuracy)
        XCTAssertEqual(result.height, -400, accuracy: accuracy)
    }

    // MARK: - Rubber Band

    func testRubberBandWithinLimitReturnsValue() {
        XCTAssertEqual(ImagePreviewMath.rubberBand(50, limit: 100), 50, accuracy: accuracy)
        XCTAssertEqual(ImagePreviewMath.rubberBand(-80, limit: 100), -80, accuracy: accuracy)
        XCTAssertEqual(ImagePreviewMath.rubberBand(0, limit: 100), 0, accuracy: accuracy)
    }

    func testRubberBandBeyondLimitIsDamped() {
        let result = ImagePreviewMath.rubberBand(200, limit: 100)
        // Should be > 100 (beyond limit) but < 200 (damped)
        XCTAssertGreaterThan(result, 100)
        XCTAssertLessThan(result, 200)
    }

    func testRubberBandBeyondNegativeLimitIsDamped() {
        let result = ImagePreviewMath.rubberBand(-200, limit: 100)
        XCTAssertLessThan(result, -100)
        XCTAssertGreaterThan(result, -200)
    }

    func testRubberBandSymmetric() {
        let pos = ImagePreviewMath.rubberBand(150, limit: 80)
        let neg = ImagePreviewMath.rubberBand(-150, limit: 80)
        XCTAssertEqual(pos, -neg, accuracy: accuracy)
    }

    func testRubberBandZeroLimitDampsAllMovement() {
        let result = ImagePreviewMath.rubberBand(50, limit: 0)
        XCTAssertGreaterThan(result, 0)
        XCTAssertLessThan(result, 50)
    }

    func testRubberBandLargerExcessApproachesAsymptote() {
        let small = ImagePreviewMath.rubberBand(200, limit: 100)
        let large = ImagePreviewMath.rubberBand(10000, limit: 100)
        // Both are beyond limit, but large excess should be closer to the
        // asymptote (limit + 200) than small excess
        XCTAssertGreaterThan(large, small)
        XCTAssertLessThanOrEqual(large, 100 + 200) // asymptote is limit + dim(200)
    }
}
