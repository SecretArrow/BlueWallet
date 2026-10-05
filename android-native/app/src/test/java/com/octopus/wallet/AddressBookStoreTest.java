package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.fail;

import org.json.JSONObject;
import org.junit.Test;

/**
 * Pure-JVM tests for address book validation (storage needs Context).
 */
public class AddressBookStoreTest {

    @Test
    public void entry_trimsAndNullProofs() {
        AddressBookStore.Entry e =
                new AddressBookStore.Entry(null, null, null);
        assertEquals("", e.id);
        assertEquals("", e.label);
        assertEquals("", e.address);
        AddressBookStore.Entry t =
                new AddressBookStore.Entry(" 1 ", " L ", " A ");
        assertEquals("1", t.id);
        assertEquals("L", t.label);
        assertEquals("A", t.address);
    }

    @Test
    public void fromJson_nullSafe() {
        assertNull(AddressBookStore.Entry.fromJson(null));
    }

    @Test
    public void requireAddress_rejectsBlank() {
        AddressBookStore.requireAddress("octABC");
        for (String bad : new String[]{null, "", "   "}) {
            try {
                AddressBookStore.requireAddress(bad);
                fail("expected IllegalArgumentException");
            } catch (IllegalArgumentException expected) {
            }
        }
    }

    @Test
    public void entry_roundTrip() throws Exception {
        AddressBookStore.Entry e = new AddressBookStore.Entry("1", "L", "A");
        JSONObject j = e.toJson();
        assertEquals("1", j.getString("id"));
    }
}
