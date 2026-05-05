import Testing
import Foundation
@testable import Marketing

@Suite("CouponCodesViewModel")
@MainActor
struct CouponCodesViewModelTests {

    private func makeCoupon(
        id: String = UUID().uuidString,
        code: String = "TEST10",
        type: CouponDiscountType = .percent,
        value: Double = 10,
        active: Bool = true
    ) -> CouponCode {
        CouponCode(
            id: id, code: code,
            discountType: type, discountValue: value,
            isActive: active
        )
    }

    @Test("initial state is empty")
    func initialState() {
        let vm = CouponCodesViewModel()
        #expect(vm.coupons.isEmpty)
        #expect(vm.showingCreate == false)
        #expect(vm.editingCoupon == nil)
        #expect(vm.confirmDelete == nil)
    }

    @Test("add appends a new coupon")
    func addCoupon() {
        let vm = CouponCodesViewModel()
        let c = makeCoupon(code: "SAVE20")
        vm.add(c)
        #expect(vm.coupons.count == 1)
        #expect(vm.coupons[0].code == "SAVE20")
    }

    @Test("add is immutable — original array unchanged")
    func addImmutable() {
        let vm = CouponCodesViewModel()
        vm.add(makeCoupon(id: "a", code: "A"))
        let snapshot = vm.coupons
        vm.add(makeCoupon(id: "b", code: "B"))
        // snapshot still has 1, new array has 2
        #expect(snapshot.count == 1)
        #expect(vm.coupons.count == 2)
    }

    @Test("update replaces coupon by id")
    func updateCoupon() {
        let vm = CouponCodesViewModel()
        let c = makeCoupon(id: "x", code: "OLD10")
        vm.add(c)
        let updated = CouponCode(
            id: "x", code: "NEW20",
            discountType: .fixedUSD, discountValue: 20,
            isActive: true
        )
        vm.update(updated)
        #expect(vm.coupons.count == 1)
        #expect(vm.coupons[0].code == "NEW20")
        #expect(vm.coupons[0].discountType == .fixedUSD)
    }

    @Test("delete removes coupon by id")
    func deleteCoupon() {
        let vm = CouponCodesViewModel()
        vm.add(makeCoupon(id: "del", code: "BYE"))
        vm.add(makeCoupon(id: "keep", code: "STAY"))
        vm.delete(id: "del")
        #expect(vm.coupons.count == 1)
        #expect(vm.coupons[0].id == "keep")
    }

    @Test("toggleActive flips isActive on matching coupon")
    func toggleActive() {
        let vm = CouponCodesViewModel()
        let c = makeCoupon(id: "t1", active: true)
        vm.add(c)
        vm.toggleActive(id: "t1")
        #expect(vm.coupons[0].isActive == false)
        vm.toggleActive(id: "t1")
        #expect(vm.coupons[0].isActive == true)
    }

    @Test("toggleActive leaves other coupons unchanged")
    func toggleActiveIsolated() {
        let vm = CouponCodesViewModel()
        vm.add(makeCoupon(id: "c1", active: true))
        vm.add(makeCoupon(id: "c2", active: true))
        vm.toggleActive(id: "c1")
        #expect(vm.coupons.first { $0.id == "c1" }?.isActive == false)
        #expect(vm.coupons.first { $0.id == "c2" }?.isActive == true)
    }

    @Test("CouponCode displayDiscount formats correctly")
    func displayDiscount() {
        let pct = CouponCode(id: "1", code: "P", discountType: .percent, discountValue: 15)
        #expect(pct.displayDiscount == "15% off")
        let fixed = CouponCode(id: "2", code: "F", discountType: .fixedUSD, discountValue: 5.50)
        #expect(fixed.displayDiscount == "$5.50 off")
        let free = CouponCode(id: "3", code: "R", discountType: .freeItem, discountValue: 0)
        #expect(free.displayDiscount == "Free item")
    }
}
