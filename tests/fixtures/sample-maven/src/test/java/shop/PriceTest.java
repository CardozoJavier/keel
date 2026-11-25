package shop;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

class PriceTest {

    @Test
    void should_add_minor_units_when_adding_two_prices() {
        assertEquals(new Price(350), new Price(100).plus(new Price(250)));
    }

    @Test
    void should_reject_a_negative_amount_when_creating_a_price() {
        assertThrows(IllegalArgumentException.class, () -> new Price(-1));
    }
}
