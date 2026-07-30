package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

type usbDeviceLocator struct {
	Bus       uint8
	PortPath  []uint8
	VendorID  uint16
	ProductID uint16
}

func (l usbDeviceLocator) canonicalID() (string, error) {
	if l.Bus == 0 {
		return "", fmt.Errorf("USB locator has no bus number")
	}
	if len(l.PortPath) == 0 {
		return "", fmt.Errorf("USB locator has no physical port path")
	}
	ports := make([]string, len(l.PortPath))
	for index, port := range l.PortPath {
		if port == 0 {
			return "", fmt.Errorf("USB locator contains an invalid port number")
		}
		ports[index] = strconv.FormatUint(uint64(port), 10)
	}
	return fmt.Sprintf(
		"go:%d:%s:%04x:%04x",
		l.Bus,
		strings.Join(ports, "."),
		l.VendorID,
		l.ProductID,
	), nil
}

func parseUSBDeviceLocator(raw string) (usbDeviceLocator, error) {
	parts := strings.Split(raw, ":")
	if len(parts) != 5 || parts[0] != "go" {
		return usbDeviceLocator{}, fmt.Errorf("invalid Go USB locator")
	}
	bus, err := strconv.ParseUint(parts[1], 10, 8)
	if err != nil || bus == 0 {
		return usbDeviceLocator{}, fmt.Errorf("invalid Go USB bus")
	}
	if parts[2] == "" {
		return usbDeviceLocator{}, fmt.Errorf("Go USB locator has no port path")
	}
	portParts := strings.Split(parts[2], ".")
	ports := make([]uint8, len(portParts))
	for index, rawPort := range portParts {
		port, parseErr := strconv.ParseUint(rawPort, 10, 8)
		if parseErr != nil || port == 0 {
			return usbDeviceLocator{}, fmt.Errorf("invalid Go USB port path")
		}
		ports[index] = uint8(port)
	}
	vendor, err := strconv.ParseUint(parts[3], 16, 16)
	if err != nil {
		return usbDeviceLocator{}, fmt.Errorf("invalid Go USB vendor ID")
	}
	product, err := strconv.ParseUint(parts[4], 16, 16)
	if err != nil {
		return usbDeviceLocator{}, fmt.Errorf("invalid Go USB product ID")
	}
	locator := usbDeviceLocator{
		Bus:       uint8(bus),
		PortPath:  ports,
		VendorID:  uint16(vendor),
		ProductID: uint16(product),
	}
	canonical, err := locator.canonicalID()
	if err != nil || canonical != raw {
		return usbDeviceLocator{}, fmt.Errorf("non-canonical Go USB locator")
	}
	return locator, nil
}

func canonicalLocatorSet(locators []usbDeviceLocator) []string {
	result := make([]string, 0, len(locators))
	for _, locator := range locators {
		if id, err := locator.canonicalID(); err == nil {
			result = append(result, id)
		}
	}
	sort.Strings(result)
	return result
}

func (l usbDeviceLocator) vendorLocator() mtp.DeviceLocator {
	return mtp.DeviceLocator{
		Bus:         l.Bus,
		PortNumbers: append([]uint8(nil), l.PortPath...),
		VendorID:    l.VendorID,
		ProductID:   l.ProductID,
	}
}

func locatorFromVendor(locator mtp.DeviceLocator) usbDeviceLocator {
	return usbDeviceLocator{
		Bus:       locator.Bus,
		PortPath:  append([]uint8(nil), locator.PortNumbers...),
		VendorID:  locator.VendorID,
		ProductID: locator.ProductID,
	}
}

func sameUSBLocator(lhs usbDeviceLocator, rhs usbDeviceLocator) bool {
	lhsID, lhsErr := lhs.canonicalID()
	rhsID, rhsErr := rhs.canonicalID()
	return lhsErr == nil && rhsErr == nil && lhsID == rhsID
}
