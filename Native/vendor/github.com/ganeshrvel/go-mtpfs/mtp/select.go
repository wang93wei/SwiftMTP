package mtp

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/ganeshrvel/usb"
)

// DeviceLocator is the stable physical USB topology identity used for exact reopen.
type DeviceLocator struct {
	Bus         uint8
	PortNumbers []uint8
	VendorID    uint16
	ProductID   uint16
}

func (l DeviceLocator) String() string {
	ports := make([]string, len(l.PortNumbers))
	for index, port := range l.PortNumbers {
		ports[index] = strconv.FormatUint(uint64(port), 10)
	}
	return fmt.Sprintf("%d:%s:%04x:%04x", l.Bus, strings.Join(ports, "."), l.VendorID, l.ProductID)
}

func (l DeviceLocator) Equal(other DeviceLocator) bool {
	if l.Bus != other.Bus || l.VendorID != other.VendorID || l.ProductID != other.ProductID ||
		len(l.PortNumbers) != len(other.PortNumbers) {
		return false
	}
	for index := range l.PortNumbers {
		if l.PortNumbers[index] != other.PortNumbers[index] {
			return false
		}
	}
	return true
}

func (d *Device) Locator() (DeviceLocator, error) {
	if d == nil || d.dev == nil {
		return DeviceLocator{}, fmt.Errorf("MTP candidate has no USB device")
	}
	ports, err := d.dev.GetPortNumbers()
	if err != nil {
		return DeviceLocator{}, fmt.Errorf("read USB port path: %w", err)
	}
	if len(ports) == 0 {
		return DeviceLocator{}, fmt.Errorf("MTP candidate has no USB port path")
	}
	return DeviceLocator{
		Bus:         d.dev.GetBusNumber(),
		PortNumbers: append([]uint8(nil), ports...),
		VendorID:    d.devDescr.IdVendor,
		ProductID:   d.devDescr.IdProduct,
	}, nil
}

func candidateFromDeviceDescriptor(d *usb.Device) *Device {
	dd, err := d.GetDeviceDescriptor()
	if err != nil {
		return nil
	}
	for i := byte(0); i < dd.NumConfigurations; i++ {
		cdecs, err := d.GetConfigDescriptor(i)
		if err != nil {
			return nil
		}
		for _, iface := range cdecs.Interfaces {
			for _, a := range iface.AltSetting {
				if len(a.EndPoints) != 3 {
					continue
				}
				m := Device{}
				for _, s := range a.EndPoints {
					switch {
					case s.Direction() == usb.ENDPOINT_IN && s.TransferType() == usb.TRANSFER_TYPE_INTERRUPT:
						m.eventEP = s.EndpointAddress
					case s.Direction() == usb.ENDPOINT_IN && s.TransferType() == usb.TRANSFER_TYPE_BULK:
						m.fetchEP = s.EndpointAddress
					case s.Direction() == usb.ENDPOINT_OUT && s.TransferType() == usb.TRANSFER_TYPE_BULK:
						m.sendEP = s.EndpointAddress
					}
				}
				if m.sendEP > 0 && m.fetchEP > 0 && m.eventEP > 0 {
					m.devDescr = *dd
					m.ifaceDescr = a
					m.dev = d.Ref()
					m.configValue = cdecs.ConfigurationValue
					return &m
				}
			}
		}
	}

	return nil
}

// FindDevices finds likely MTP devices without opening them.
func FindDevices(c *usb.Context) ([]*Device, error) {
	l, err := c.GetDeviceList()
	if err != nil {
		return nil, err
	}

	var cands []*Device
	for _, d := range l {
		cand := candidateFromDeviceDescriptor(d)
		if cand != nil {
			cands = append(cands, cand)
		}
	}

	if len(l) > 0 {
		l.Done()
	}

	return cands, nil
}

// FindDeviceLocators enumerates MTP candidates without opening them.
func FindDeviceLocators() ([]DeviceLocator, error) {
	context := usb.NewContext()
	candidates, err := FindDevices(context)
	if err != nil {
		context.Exit()
		return nil, err
	}
	defer func() {
		for _, candidate := range candidates {
			candidate.Done()
		}
		context.Exit()
	}()

	locators := make([]DeviceLocator, 0, len(candidates))
	for _, candidate := range candidates {
		locator, err := candidate.Locator()
		if err != nil {
			return nil, err
		}
		locators = append(locators, locator)
	}
	return locators, nil
}

func configureSelectedDevice(candidate *Device, id string) (*Device, error) {
	config, err := candidate.h.GetConfiguration()
	if err != nil {
		return nil, fmt.Errorf("could not get configuration of %v: %v", id, err)
	}
	if config != candidate.configValue {
		if err := candidate.h.SetConfiguration(candidate.configValue); err != nil {
			return nil, fmt.Errorf("could not set configuration of %v: %v", id, err)
		}
	}
	return candidate, nil
}

// SelectDeviceByLocator opens only the candidate matching the complete topology locator.
func SelectDeviceByLocator(locator DeviceLocator, allowDebugging bool) (*Device, error) {
	if len(locator.PortNumbers) == 0 {
		return nil, fmt.Errorf("MTP locator has no USB port path")
	}
	context := usb.NewContext()
	candidates, err := FindDevices(context)
	if err != nil {
		context.Exit()
		return nil, err
	}

	var selected *Device
	for _, candidate := range candidates {
		candidateLocator, locatorErr := candidate.Locator()
		if locatorErr != nil {
			for _, cleanup := range candidates {
				cleanup.Done()
			}
			context.Exit()
			return nil, locatorErr
		}
		if candidateLocator.Equal(locator) {
			if selected != nil {
				for _, cleanup := range candidates {
					cleanup.Done()
				}
				context.Exit()
				return nil, fmt.Errorf("multiple MTP candidates matched exact USB locator")
			}
			selected = candidate
		}
	}
	if selected == nil {
		for _, candidate := range candidates {
			candidate.Done()
		}
		context.Exit()
		return nil, fmt.Errorf("no MTP device matched exact USB locator")
	}

	for _, candidate := range candidates {
		if candidate != selected {
			candidate.Done()
		}
	}
	selected.ctx = context
	selected.USBDebug = allowDebugging
	selected.DataDebug = allowDebugging
	selected.MTPDebug = allowDebugging
	if err := selected.Open(); err != nil {
		selected.Done()
		return nil, err
	}
	configured, err := configureSelectedDevice(selected, locator.String())
	if err != nil {
		selected.Close()
		selected.Done()
		return nil, err
	}
	return configured, nil
}

// selectDevice finds a device that matches given pattern
func selectDevice(cands []*Device, pattern string) (*Device, error) {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return nil, err
	}

	var found []*Device
	for _, cand := range cands {
		if err := cand.Open(); err != nil {
			continue
		}

		found = append(found, cand)
	}

	if len(found) == 0 {
		return nil, fmt.Errorf("no MTP devices found")
	}

	cands = found
	found = nil
	var ids []string
	for i, cand := range cands {
		id, err := cand.ID()
		if err != nil {
			// TODO - close cands
			return nil, fmt.Errorf("Id dev %d: %v", i, err)
		}

		if pattern == "" || re.FindString(id) != "" {
			found = append(found, cand)
			ids = append(ids, id)
		} else {
			cand.Close()
			cand.Done()
		}
	}

	if len(found) == 0 {
		return nil, fmt.Errorf("no device matched")
	}

	if len(found) > 1 {
		return nil, fmt.Errorf("mtp: more than 1 device: %s", strings.Join(ids, ","))
	}

	cand := found[0]
	return configureSelectedDevice(cand, ids[0])
}

// SelectDevice returns opened MTP device that matches the given pattern.
func SelectDevice(pattern string) (*Device, error) {
	c := usb.NewContext()

	devs, err := FindDevices(c)
	if err != nil {
		return nil, err
	}
	if len(devs) == 0 {
		return nil, fmt.Errorf("no MTP devices found")
	}

	return selectDevice(devs, pattern)
}

// SelectDeviceForDebugging returns opened MTP device that matches the given pattern and debug information are set true
func SelectDeviceWithDebugging(pattern string, allowDebugging bool) (*Device, error) {
	c := usb.NewContext()

	devs, err := FindDevices(c)
	if err != nil {
		return nil, err
	}
	if len(devs) == 0 {
		return nil, fmt.Errorf("no MTP devices found")
	}

	if allowDebugging {
		for _, _dev := range devs {
			_dev.USBDebug = allowDebugging
			_dev.DataDebug = allowDebugging
			_dev.MTPDebug = allowDebugging
		}
	}

	return selectDevice(devs, pattern)
}
