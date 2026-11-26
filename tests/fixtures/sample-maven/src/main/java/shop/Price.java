package shop;

/** A price in minor units (cents). */
public record Price(long minor) {
    public Price {
        if (minor < 0) {
            throw new IllegalArgumentException("price must not be negative");
        }
    }

    public Price plus(Price other) {
        return new Price(Math.addExact(minor, other.minor));
    }
}
