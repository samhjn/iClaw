import XCTest
@testable import iClaw

final class ImagePreviewZoomTests: XCTestCase {

    private let viewport = CGSize(width: 400, height: 800)
    private let accuracy: CGFloat = 0.001

    // MARK: - Zoom Anchor Offset

    func testZoomAtCenterProducesZeroOffset() {
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.5, anchorUnitY: 0.5,
            viewportSize: viewport,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        XCTAssertEqual(offset.width, 0, accuracy: accuracy)
        XCTAssertEqual(offset.height, 0, accuracy: accuracy)
    }

    func testZoomAtTopLeftShiftsImageTowardTopLeft() {
        // Pinch at top-left corner (0, 0)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.0, anchorUnitY: 0.0,
            viewportSize: viewport,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        // Anchor is at (-200, -400) from center; ratio = 2
        // offset = (-200)*(1-2) + 0 = 200, (-400)*(1-2) + 0 = 400
        XCTAssertEqual(offset.width, 200, accuracy: accuracy)
        XCTAssertEqual(offset.height, 400, accuracy: accuracy)
    }

    func testZoomAtBottomRightShiftsImageTowardBottomRight() {
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 1.0, anchorUnitY: 1.0,
            viewportSize: viewport,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: .zero
        )
        XCTAssertEqual(offset.width, -200, accuracy: accuracy)
        XCTAssertEqual(offset.height, -400, accuracy: accuracy)
    }

    func testZoomPreservesExistingPanOffset() {
        let existing = CGSize(width: 50, height: -30)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.5, anchorUnitY: 0.5,
            viewportSize: viewport,
            lastScale: 1.0, newScale: 2.0,
            lastPanOffset: existing
        )
        // Center anchor: anchorX=0, anchorY=0; ratio=2
        // offset = 0*(1-2) + existing*2 = existing*2
        XCTAssertEqual(offset.width, 100, accuracy: accuracy)
        XCTAssertEqual(offset.height, -60, accuracy: accuracy)
    }

    func testZoomOutTowardsScale1ReducesOffset() {
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.25, anchorUnitY: 0.25,
            viewportSize: viewport,
            lastScale: 2.0, newScale: 1.0,
            lastPanOffset: CGSize(width: 100, height: 200)
        )
        // anchor = (-100, -200), ratio = 0.5
        // w = -100*(1-0.5) + 100*0.5 = -50 + 50 = 0
        // h = -200*(1-0.5) + 200*0.5 = -100 + 100 = 0
        XCTAssertEqual(offset.width, 0, accuracy: accuracy)
        XCTAssertEqual(offset.height, 0, accuracy: accuracy)
    }

    func testZoomNoChangeReturnsLastPanOffset() {
        let existing = CGSize(width: 42, height: -17)
        let offset = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: 0.3, anchorUnitY: 0.7,
            viewportSize: viewport,
            lastScale: 2.0, newScale: 2.0,
            lastPanOffset: existing
        )
        // ratio = 1, so offset = anchor*(1-1) + existing*1 = existing
        XCTAssertEqual(offset.width, existing.width, accuracy: accuracy)
        XCTAssertEqual(offset.height, existing.height, accuracy: accuracy)
    }

    func testZoomAnchorOffsetIsLinearInMagnification() {
        // Zooming from 1→2 then 2→3 should give the same result as 1→3
        // when the anchor and initial offset are the same for the 1→3 case.
        let anchorX: CGFloat = 0.25
        let anchorY: CGFloat = 0.75

        let step1 = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: anchorX, anchorUnitY: anchorY,
            viewportSize: viewport,
            lastScale: 1.0, newScale: 3.0,
            lastPanOffset: .zero
        )

        let direct = ImagePreviewMath.zoomAnchorOffset(
            anchorUnitX: anchorX, anchorUnitY: anchorY,
            viewportSize: viewport,
            lastScale: 1.0, newScale: 3.0,
            lastPanOffset: .zero
        )

        XCTAssertEqual(step1.width, direct.width, accuracy: accuracy)
        XCTAssertEqual(step1.height, direct.height, accuracy: accuracy)
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
