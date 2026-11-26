package weak;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

// Seeded weaknesses (keel T059), on purpose:
// - the branch above 10,000,000 is never exercised (untested branch);
// - the two minimum-fee tests kill exactly the same mutants (duplicate tests);
// - the large-amount test asserts nothing (missing assertion).
class FeeCalculatorTest {

    private final FeeCalculator calculator = new FeeCalculator();

    @Test
    void should_charge_minimum_fee_when_amount_is_small() {
        assertEquals(30, calculator.feeMinor(100));
    }

    @Test
    void should_charge_minimum_fee_when_amount_is_tiny() {
        assertEquals(30, calculator.feeMinor(200));
    }

    @Test
    void should_compute_fee_when_amount_is_large() {
        calculator.feeMinor(1_000_000);
    }
}
